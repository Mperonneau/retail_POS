"""Cash drawer sessions. Same arithmetic as the register's cash control screen."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone

from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.money import ZERO, money

from .models import CashMovement, CashSession, ShiftHandoff


@dataclass
class DrawerTotals:
    opening_htg: Decimal
    opening_usd: Decimal
    in_htg: Decimal
    in_usd: Decimal
    out_htg: Decimal
    out_usd: Decimal
    adjust_htg: Decimal
    adjust_usd: Decimal

    @property
    def expected_htg(self) -> Decimal:
        return money(self.opening_htg + self.in_htg - self.out_htg + self.adjust_htg)

    @property
    def expected_usd(self) -> Decimal:
        return money(self.opening_usd + self.in_usd - self.out_usd + self.adjust_usd)


def _sum(queryset, expression: str) -> Decimal:
    return money(queryset.aggregate(v=Sum(expression))["v"] or 0)


def drawer_totals(session: CashSession) -> DrawerTotals:
    from django.db.models import F

    drawer = session.movements.filter(tender__in=CashMovement.DRAWER_TENDERS)
    ins = drawer.filter(type=CashMovement.CASH_IN)
    outs = drawer.filter(type=CashMovement.CASH_OUT)
    adjust = drawer.filter(type=CashMovement.ADJUSTMENT)
    totals = {
        "in_htg": ins.aggregate(v=Sum(F("amount_htg") + F("tips_htg")))["v"],
        "in_usd": ins.aggregate(v=Sum(F("amount_usd") + F("tips_usd")))["v"],
        "out_htg": outs.aggregate(v=Sum(F("amount_htg") + F("tips_htg")))["v"],
        "out_usd": outs.aggregate(v=Sum(F("amount_usd") + F("tips_usd")))["v"],
    }
    return DrawerTotals(
        opening_htg=money(session.opening_htg),
        opening_usd=money(session.opening_usd),
        in_htg=money(totals["in_htg"] or 0),
        in_usd=money(totals["in_usd"] or 0),
        out_htg=money(totals["out_htg"] or 0),
        out_usd=money(totals["out_usd"] or 0),
        adjust_htg=_sum(adjust, "amount_htg"),
        adjust_usd=_sum(adjust, "amount_usd"),
    )


def tender_breakdown(session: CashSession) -> list[dict]:
    rows = []
    for tender, label in CashMovement.TENDERS:
        movements = session.movements.filter(tender=tender)
        ins = movements.filter(type=CashMovement.CASH_IN)
        outs = movements.filter(type=CashMovement.CASH_OUT)
        adjust = movements.filter(type=CashMovement.ADJUSTMENT)
        net_htg = _sum(ins, "amount_htg") + _sum(ins, "tips_htg") - _sum(outs, "amount_htg") - _sum(outs, "tips_htg") + _sum(adjust, "amount_htg")
        net_usd = _sum(ins, "amount_usd") + _sum(ins, "tips_usd") - _sum(outs, "amount_usd") - _sum(outs, "tips_usd") + _sum(adjust, "amount_usd")
        rows.append({"tender": tender, "label": label, "net_htg": money(net_htg), "net_usd": money(net_usd),
                     "count": movements.count()})
    return rows


def open_session_for(location) -> CashSession | None:
    if location is None:
        return None
    return CashSession.objects.filter(location=location, status=CashSession.OPEN).first()


def open_session(actor, *, location, opening_htg, opening_usd=0) -> CashSession:
    if location is None:
        raise ApiError("Choisissez le point de vente.")
    opening_htg = money(opening_htg)
    opening_usd = money(opening_usd)
    if opening_htg < 0 or opening_usd < 0:
        raise ApiError("Le fonds de caisse ne peut pas être négatif.")
    try:
        with transaction.atomic():
            session = CashSession.objects.create(
                business=actor.business,
                location=location,
                opened_by=actor,
                opened_by_name=actor.full_name,
                opening_htg=opening_htg,
                opening_usd=opening_usd,
            )
    except IntegrityError as exc:
        raise ApiError("Une caisse est déjà ouverte pour ce point de vente.", 409) from exc
    audit(actor.business, "cash.opened", actor=actor, target=session, opening_htg=str(opening_htg),
          opening_usd=str(opening_usd))
    return session


def add_movement(actor, session: CashSession, *, type: str, tender: str = CashMovement.CASH_HTG, amount_htg=0,
                 amount_usd=0, tips_htg=0, tips_usd=0, description: str, order=None, reference: str = "",
                 recorded_by_name: str = "") -> CashMovement:
    if session.status != CashSession.OPEN:
        raise ApiError("Cette caisse est fermée.", 409)
    if type not in dict(CashMovement.TYPES):
        raise ApiError("Type de mouvement inconnu.")
    if tender not in dict(CashMovement.TENDERS):
        raise ApiError("Mode de paiement inconnu.")
    values = [money(amount_htg), money(amount_usd), money(tips_htg), money(tips_usd)]
    if type != CashMovement.ADJUSTMENT and any(v < 0 for v in values):
        raise ApiError("Les montants doivent être positifs.")
    if all(v == 0 for v in values):
        raise ApiError("Indiquez un montant.")
    if not description.strip():
        raise ApiError("Ajoutez une description.")
    from apps.accounts.models import StaffMember

    movement = CashMovement.objects.create(
        business=session.business,
        session=session,
        type=type,
        tender=tender,
        amount_htg=values[0],
        amount_usd=values[1],
        tips_htg=values[2],
        tips_usd=values[3],
        description=description[:200],
        order=order,
        reference=reference[:40],
        recorded_by=actor if isinstance(actor, StaffMember) else None,
        recorded_by_name=recorded_by_name or getattr(actor, "full_name", "") or "Système",
    )
    if order is None:
        audit(session.business, f"cash.{type}", actor=actor if isinstance(actor, StaffMember) else None,
              target=movement, tender=tender, amount_htg=str(values[0]), amount_usd=str(values[1]))
    return movement


def handoff(actor, session: CashSession, *, received_by=None, received_by_name: str = "", counted_htg, counted_usd=0,
            note: str = "") -> ShiftHandoff:
    if session.status != CashSession.OPEN:
        raise ApiError("Cette caisse est fermée.", 409)
    totals = drawer_totals(session)
    record = ShiftHandoff.objects.create(
        business=session.business,
        session=session,
        closed_by=actor,
        closed_by_name=actor.full_name,
        received_by=received_by,
        received_by_name=(received_by.full_name if received_by else received_by_name)[:120] or "—",
        opening_htg=totals.opening_htg,
        opening_usd=totals.opening_usd,
        inflow_htg=totals.in_htg,
        inflow_usd=totals.in_usd,
        outflow_htg=totals.out_htg,
        outflow_usd=totals.out_usd,
        expected_htg=totals.expected_htg,
        expected_usd=totals.expected_usd,
        counted_htg=money(counted_htg),
        counted_usd=money(counted_usd),
        note=note[:500],
    )
    audit(session.business, "cash.handoff", actor=actor, target=session,
          delta_htg=str(record.counted_htg - record.expected_htg), delta_usd=str(record.counted_usd - record.expected_usd))
    return record


@transaction.atomic
def close_session(actor, session: CashSession, *, counted_htg=None, counted_usd=None, note: str = "") -> CashSession:
    session = CashSession.objects.select_for_update().get(pk=session.pk)
    if session.status != CashSession.OPEN:
        raise ApiError("Cette caisse est déjà fermée.", 409)
    totals = drawer_totals(session)
    # Adjustments are folded into the ins so the saved Attendu matches the drawer.
    session.total_in_htg = money(totals.in_htg + totals.adjust_htg)
    session.total_in_usd = money(totals.in_usd + totals.adjust_usd)
    session.total_out_htg = totals.out_htg
    session.total_out_usd = totals.out_usd
    session.expected_htg = totals.expected_htg
    session.expected_usd = totals.expected_usd
    session.counted_htg = money(counted_htg) if counted_htg not in (None, "") else totals.expected_htg
    session.counted_usd = money(counted_usd) if counted_usd not in (None, "") else totals.expected_usd
    session.over_short_htg = money(session.counted_htg - session.expected_htg)
    session.over_short_usd = money(session.counted_usd - session.expected_usd)
    session.status = CashSession.CLOSED
    session.closed_at = timezone.now()
    session.closed_by = actor
    session.closed_by_name = actor.full_name
    session.closing_note = note[:1000]
    session.save()
    audit(session.business, "cash.closed", actor=actor, target=session, over_short_htg=str(session.over_short_htg),
          over_short_usd=str(session.over_short_usd))
    if abs(session.over_short_htg) >= 1 or abs(session.over_short_usd) >= Decimal("0.01"):
        from apps.notifications.services import notify

        notify(session.business, "cash_variance", "Écart de caisse",
               f"{session.location.name} : {session.over_short_htg} HTG / {session.over_short_usd} USD",
               session_id=str(session.pk))
    return session


TENDER_FOR_METHOD = {
    "cash": CashMovement.CASH_HTG,
    "cashHtg": CashMovement.CASH_HTG,
    "cashUsd": CashMovement.CASH_USD,
    "moncash": CashMovement.MONCASH,
    "card": CashMovement.CARD,
    "check": CashMovement.CHECK,
}


def record_customer_payment(actor, entry, method: str, amount_usd=None, *, location=None) -> None:
    """Account payments collected at the register also move the drawer."""
    tender = TENDER_FOR_METHOD.get(method)
    if tender is None:
        return
    session = open_session_for(location)
    if session is None:
        return
    usd = money(amount_usd or 0)
    add_movement(
        actor, session, type=CashMovement.CASH_IN, tender=tender,
        amount_htg=ZERO if tender == CashMovement.CASH_USD and usd else entry.amount_htg,
        amount_usd=usd if tender == CashMovement.CASH_USD else ZERO,
        description=f"Paiement compte — {entry.customer.name}", reference=entry.receipt_number,
    )

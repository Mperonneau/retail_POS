"""Sales: ring up, collect, clear checks, refund, cancel.

Totals follow the register's RetailOrder: discount on the subtotal, then the
delivery fee, tax on the subtotal, and the service fee only when the order
was paid electronically.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from django.db import transaction
from django.db.models import F
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime

from apps.accounts import roles
from apps.accounts.models import StaffMember
from apps.accounts.services import check_discount_code
from apps.cash.models import CashMovement
from apps.cash.services import TENDER_FOR_METHOD, add_movement, open_session_for
from apps.catalog.models import Product, StockMovement
from apps.catalog.pricing import parse_quantity, price_line
from apps.catalog.stock import adjust_stock
from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.images import save_private_image
from apps.common.money import EPSILON, ZERO, money, percent_of
from apps.common.numbering import next_number
from apps.customers import ledger
from apps.customers.models import Customer
from apps.payments.models import CheckPayment, Payment

from .models import (
    Fulfillment,
    Order,
    OrderLine,
    OrderSource,
    OrderStatus,
    OrderStatusEvent,
    Quote,
    QuoteLine,
    QuoteStatus,
    Refund,
    RefundLine,
)

MAX_LINES = 200
MAX_PAYMENTS = 10
# Rates far from the configured one are a typo, not a real offline quote.
RATE_TOLERANCE = Decimal("0.25")


@dataclass
class Totals:
    subtotal: Decimal
    discount: Decimal
    delivery_fee: Decimal
    tax: Decimal
    service: Decimal

    @property
    def total(self) -> Decimal:
        return money(self.subtotal - self.discount + self.delivery_fee + self.tax + self.service)


def compute_totals(subtotal, *, discount_percent=0, delivery_fee=0, tax_percent=0, service_percent=0,
                   electronic: bool = False, discount_amount=None) -> Totals:
    subtotal = money(subtotal)
    discount = percent_of(subtotal, discount_percent) if discount_amount is None else min(money(discount_amount), subtotal)
    return Totals(
        subtotal=subtotal,
        discount=discount,
        delivery_fee=money(delivery_fee),
        tax=percent_of(subtotal, tax_percent),
        service=percent_of(subtotal, service_percent) if electronic else ZERO,
    )


def status_after_full_payment(fulfillment_mode: str) -> str:
    return OrderStatus.COMPLETED if fulfillment_mode == Fulfillment.PICKUP else OrderStatus.PAID


def _actor_name(actor) -> str:
    return actor.full_name if isinstance(actor, StaffMember) else str(actor or "Système")[:120]


def _staff(actor):
    return actor if isinstance(actor, StaffMember) else None


def _parse_uuid(raw, message: str = "Identifiant invalide."):
    if raw in (None, ""):
        return None
    try:
        return uuid.UUID(str(raw))
    except (TypeError, ValueError, AttributeError) as exc:
        raise ApiError(message) from exc


def _resolve_rate(business, raw) -> Decimal:
    configured = business.settings.effective_usd_rate()
    if raw in (None, ""):
        return configured
    rate = Decimal(str(money(raw)))
    if rate <= 0 or abs(rate - configured) > configured * RATE_TOLERANCE:
        raise ApiError("Taux du dollar invalide.")
    return rate


def _customer(business, raw_id) -> Customer | None:
    pk = _parse_uuid(raw_id, "Client invalide.")
    if pk is None:
        return None
    customer = Customer.objects.filter(business=business, pk=pk).first()
    if customer is None:
        raise ApiError("Client introuvable.", 404)
    return customer


def _record_status(order: Order, from_status: str, actor, note: str = "") -> None:
    OrderStatusEvent.objects.create(order=order, from_status=from_status, to_status=order.status,
                                    actor=_staff(actor), actor_name=_actor_name(actor), note=note[:300])


# --- Lines -------------------------------------------------------------------


@dataclass
class LineDraft:
    product: Product | None
    name: str
    quantity: int
    unit_price: Decimal
    unit_cost: Decimal
    stock_units: int
    measure: str
    width: int
    options_label: str
    options: list
    overridden: bool

    @property
    def line_total(self) -> Decimal:
        return money(self.unit_price * self.quantity)


def build_lines(business, raw_lines, actor) -> list[LineDraft]:
    if not isinstance(raw_lines, list) or not raw_lines:
        raise ApiError("Le panier est vide.")
    if len(raw_lines) > MAX_LINES:
        raise ApiError("Trop d'articles dans le panier.")
    ids = {_parse_uuid(line.get("product_id") or line.get("product"), "Article invalide.")
           for line in raw_lines if isinstance(line, dict) and (line.get("product_id") or line.get("product"))}
    products = {
        p.pk: p
        for p in Product.objects.filter(business=business, pk__in=ids).prefetch_related("option_groups__choices")
    }
    can_override = hasattr(actor, "has_perm_code") and actor.has_perm_code(roles.CATALOG_MANAGE)
    drafts: list[LineDraft] = []
    for raw in raw_lines:
        if not isinstance(raw, dict):
            raise ApiError("Article invalide.")
        product_id = _parse_uuid(raw.get("product_id") or raw.get("product"), "Article invalide.")
        override = raw.get("unit_price_htg")
        if product_id is None:
            name = str(raw.get("name") or "").strip()[:120]
            if not name:
                raise ApiError("Donnez un nom à l'article libre.")
            price = money(override)
            if price <= 0:
                raise ApiError(f"Indiquez le prix de {name}.")
            drafts.append(LineDraft(None, name, parse_quantity(raw.get("quantity")), price, ZERO, 0, "", 0, "", [],
                                    True))
            continue
        product = products.get(product_id)
        if product is None:
            raise ApiError("Un article du panier n'existe plus.", 409)
        priced = price_line(product, quantity=raw.get("quantity"), measure=raw.get("measure"),
                            width=raw.get("width"), choices=raw.get("choices"))
        unit_price = priced.unit_price
        overridden = False
        if override not in (None, "") and money(override) != unit_price:
            if not can_override:
                raise ApiError("Vous n'avez pas l'autorisation de modifier un prix.", 403)
            unit_price = money(override)
            if unit_price < 0:
                raise ApiError("Prix invalide.")
            overridden = True
        drafts.append(LineDraft(
            product=product,
            name=product.name,
            quantity=priced.quantity,
            unit_price=unit_price,
            unit_cost=money(product.cost_htg * priced.stock_units_each) if product.cost_htg else ZERO,
            stock_units=priced.stock_units,
            measure=priced.measure,
            width=priced.width,
            options_label=priced.options_label,
            options=priced.options,
            overridden=overridden,
        ))
    return drafts


def _save_lines(order: Order, drafts: list[LineDraft]) -> None:
    OrderLine.objects.bulk_create([
        OrderLine(
            order=order,
            product=d.product,
            product_name=d.name,
            options_label=d.options_label[:300],
            options=d.options,
            measure=d.measure,
            width=d.width,
            quantity=d.quantity,
            unit_price_htg=d.unit_price,
            unit_price_usd=d.product.price_usd if d.product and d.product.price_usd else None,
            unit_cost_htg=d.unit_cost,
            line_total_htg=d.line_total,
            stock_units=d.stock_units,
            price_overridden=d.overridden,
        )
        for d in drafts
    ])


# --- Payments ----------------------------------------------------------------


@dataclass
class TenderDraft:
    method: str
    amount_htg: Decimal
    amount_usd: Decimal
    tendered_htg: Decimal
    change_htg: Decimal
    reference: str
    last_four: str
    check: dict | None


def parse_tenders(raw_payments, rate: Decimal) -> list[TenderDraft]:
    if raw_payments in (None, ""):
        return []
    if not isinstance(raw_payments, list) or len(raw_payments) > MAX_PAYMENTS:
        raise ApiError("Paiements invalides.")
    methods = dict(Payment.METHODS)
    tenders = []
    for raw in raw_payments:
        if not isinstance(raw, dict):
            raise ApiError("Paiement invalide.")
        method = str(raw.get("method") or "")
        if method == "cashHtg":
            method = Payment.CASH
        if method not in methods:
            raise ApiError("Mode de paiement inconnu.")
        amount_usd = money(raw.get("amount_usd"))
        amount = money(raw.get("amount_htg"))
        if amount <= 0 and amount_usd > 0:
            amount = money(amount_usd * rate)
        if amount <= 0:
            raise ApiError("Chaque paiement doit avoir un montant.")
        tendered = money(raw.get("tendered_htg"))
        change = money(tendered - amount) if tendered > amount else ZERO
        check = raw.get("check") if method == Payment.CHECK else None
        if method == Payment.CHECK:
            if not isinstance(check, dict):
                raise ApiError("Ajoutez les informations du chèque.")
            for key, label in (("number", "le numéro"), ("bank", "la banque"), ("payer_name", "le nom du payeur")):
                if not str(check.get(key) or "").strip():
                    raise ApiError(f"Indiquez {label} du chèque.")
        tenders.append(TenderDraft(
            method=method,
            amount_htg=amount,
            amount_usd=amount_usd,
            tendered_htg=tendered,
            change_htg=change,
            reference=str(raw.get("reference") or "")[:120],
            last_four="".join(ch for ch in str(raw.get("last_four") or "") if ch.isdigit())[-4:],
            check=check,
        ))
    return tenders


def _create_payment(order: Order, tender: TenderDraft, actor, *, paylink=None) -> Payment:
    payment = Payment.objects.create(
        business=order.business,
        order=order,
        method=tender.method,
        status=Payment.PENDING if tender.method == Payment.CHECK else Payment.CONFIRMED,
        amount_htg=tender.amount_htg,
        amount_usd=tender.amount_usd,
        tendered_htg=tender.tendered_htg,
        change_htg=tender.change_htg,
        reference=tender.reference,
        last_four=tender.last_four,
        recorded_by=_staff(actor),
        recorded_by_name=_actor_name(actor),
        paylink=paylink,
    )
    if tender.check is not None:
        info = tender.check
        image = ""
        if info.get("image_data_url"):
            image = save_private_image(str(info["image_data_url"]), "checks")
        check_date = info.get("check_date")
        parsed_date = check_date if isinstance(check_date, date) else parse_date(str(check_date or ""))
        CheckPayment.objects.create(
            business=order.business,
            payment=payment,
            number=str(info.get("number")).strip()[:40],
            bank=str(info.get("bank")).strip()[:80],
            payer_name=str(info.get("payer_name")).strip()[:120],
            check_date=parsed_date or timezone.localdate(),
            image=image,
            amount_htg=tender.amount_htg,
            credit_customer=order.customer,
        )
    return payment


def _cash_movement_for(order: Order, tender: TenderDraft, actor, session, *, out: bool = False,
                       description: str = "") -> None:
    cash_tender = TENDER_FOR_METHOD.get(tender.method)
    if cash_tender is None or session is None:
        return
    usd_bills = cash_tender == CashMovement.CASH_USD
    add_movement(
        actor, session,
        type=CashMovement.CASH_OUT if out else CashMovement.CASH_IN,
        tender=cash_tender,
        amount_htg=ZERO if usd_bills else tender.amount_htg,
        amount_usd=(tender.amount_usd or money(tender.amount_htg / order.usd_rate)) if usd_bills else ZERO,
        description=description or f"Vente {order.number}",
        order=order,
        reference=order.number,
        recorded_by_name=_actor_name(actor),
    )


def _require_session(business, location, tenders) -> object:
    session = open_session_for(location)
    needs_drawer = any(TENDER_FOR_METHOD.get(t.method) in CashMovement.DRAWER_TENDERS for t in tenders)
    if session is None and needs_drawer and business.settings.require_open_cash_session:
        raise ApiError("Ouvrez la caisse avant d'encaisser des espèces.", 409)
    return session


def _derive_status(order: Order) -> str:
    if order.payments.filter(method=Payment.CHECK, status=Payment.PENDING).exists():
        return OrderStatus.CHECK_PENDING
    if order.balance_due_htg > EPSILON:
        return OrderStatus.PARTIALLY_PAID
    return status_after_full_payment(order.fulfillment_mode)


# --- Create ------------------------------------------------------------------


def _validate_fulfillment(business, mode: str, data: dict) -> None:
    if mode not in dict(Fulfillment.CHOICES):
        raise ApiError("Mode de remise inconnu.")
    settings = business.settings
    if mode == Fulfillment.PICKUP and not settings.pickup_enabled:
        raise ApiError("Le retrait n'est pas activé.")
    if mode == Fulfillment.DELIVERY:
        if not settings.delivery_enabled:
            raise ApiError("La livraison n'est pas activée.")
        if not str(data.get("delivery_location") or "").strip():
            raise ApiError("Indiquez l'adresse de livraison.")


def _check_discount(business, actor, percent: Decimal, code: str) -> StaffMember | None:
    if percent <= 0:
        return None
    if percent > 100:
        raise ApiError("Remise invalide.")
    settings = business.settings
    if not settings.discounts_allowed:
        raise ApiError("Les remises sont désactivées.", 403)
    if isinstance(actor, StaffMember) and actor.role in (roles.OWNER, roles.ADMIN):
        return actor
    if settings.discount_approval_code_hash and not check_discount_code(settings, code or ""):
        raise ApiError("Code d'approbation de remise incorrect.", 403)
    return None


@transaction.atomic
def create_sale(actor, data: dict, *, location=None, device=None, source: str = OrderSource.POS,
                paylink=None, discount_preapproved: bool = False, apply_fees: bool = True,
                record_cash: bool = True) -> tuple[Order, bool]:
    """Ring up a sale. Returns (order, created). Replaying the same id is a no-op.

    Vitrine orders pass apply_fees=False (the shopper already paid the quoted
    total) and record_cash=False (online money never enters a drawer).
    """
    business = actor.business
    order_id = _parse_uuid(data.get("id"), "Identifiant de vente invalide.") or uuid.uuid4()
    existing = Order.objects.filter(pk=order_id).first()
    if existing is not None:
        if existing.business_id != business.pk:
            raise ApiError("Identifiant de vente déjà utilisé.", 409)
        return existing, False

    settings = business.settings
    rate = _resolve_rate(business, data.get("usd_rate"))
    drafts = build_lines(business, data.get("lines"), actor)
    tenders = parse_tenders(data.get("payments"), rate)
    customer = _customer(business, data.get("customer_id") or data.get("customer"))
    mode = str(data.get("fulfillment_mode") or Fulfillment.IN_STORE)
    _validate_fulfillment(business, mode, data)
    discount_percent = money(data.get("discount_percent"))
    if discount_preapproved:
        if discount_percent < 0 or discount_percent > 100:
            raise ApiError("Remise invalide.")
        approver = None
    else:
        approver = _check_discount(business, actor, discount_percent, str(data.get("discount_code") or ""))
    delivery_fee = money(data.get("delivery_fee_htg")) if mode == Fulfillment.DELIVERY else ZERO
    if delivery_fee < 0:
        raise ApiError("Frais de livraison invalides.")

    electronic = any(t.method in Payment.ELECTRONIC for t in tenders)
    tax_percent = settings.tax_percent if settings.tax_enabled and apply_fees else ZERO
    service_percent = settings.service_fee_percent if settings.service_fee_enabled and apply_fees else ZERO
    fixed_discount = data.get("discount_htg") if discount_preapproved and data.get("discount_htg") else None
    totals = compute_totals(
        sum((d.line_total for d in drafts), ZERO),
        discount_percent=discount_percent,
        delivery_fee=delivery_fee,
        tax_percent=tax_percent,
        service_percent=service_percent,
        electronic=electronic,
        discount_amount=fixed_discount,
    )
    total = totals.total

    applied = money(sum((t.amount_htg for t in tenders), ZERO))
    if applied > total + EPSILON:
        raise ApiError("Les paiements dépassent le total de la vente.")
    credit_tenders = [t for t in tenders if t.method == Payment.CREDIT]
    store_credit_tenders = [t for t in tenders if t.method == Payment.STORE_CREDIT]
    remainder = money(total - applied)
    if remainder > EPSILON and not data.get("charge_remainder_to_credit"):
        raise ApiError(f"Il reste {remainder} HTG à payer.")
    credited = money(sum((t.amount_htg for t in credit_tenders), ZERO) + max(remainder, ZERO))
    if (credited > 0 or store_credit_tenders) and customer is None:
        raise ApiError("Choisissez le client pour le crédit ou l'avoir.")
    if credited > 0:
        ledger.ensure_credit_allowed(customer, credited, actor)
    session = _require_session(business, location, tenders) if record_cash else None

    client_created = parse_datetime(str(data.get("client_created_at") or "")) if data.get("client_created_at") else None
    order = Order.objects.create(
        id=order_id,
        business=business,
        number=next_number(business, "ORD"),
        source=source,
        location=location,
        device=device,
        customer=customer,
        client_name=str(data.get("client_name") or (customer.name if customer else ""))[:120],
        client_phone=str(data.get("client_phone") or (customer.phone if customer else ""))[:40],
        client_email=str(data.get("client_email") or (customer.email if customer else ""))[:254],
        fulfillment_mode=mode,
        delivery_location=str(data.get("delivery_location") or "")[:300],
        delivery_phone=str(data.get("delivery_phone") or "")[:40],
        delivery_fee_htg=totals.delivery_fee,
        discount_percent=discount_percent,
        discount_approved_by=approver,
        tax_percent=tax_percent,
        service_charge_percent=service_percent if electronic else ZERO,
        subtotal_htg=totals.subtotal,
        discount_htg=totals.discount,
        tax_htg=totals.tax,
        service_charge_htg=totals.service,
        total_htg=total,
        amount_paid_htg=money(total - credited),
        balance_due_htg=credited,
        usd_rate=rate,
        payment_method=tenders[0].method if len(tenders) == 1 else ("split" if tenders else Payment.CREDIT)[:12],
        payment_last_four=next((t.last_four for t in tenders if t.last_four), ""),
        recorded_by=_staff(actor),
        recorded_by_name=_actor_name(actor),
        note=str(data.get("note") or "")[:500],
        client_created_at=client_created,
        paid_at=timezone.now(),
    )
    _save_lines(order, drafts)

    for tender in tenders:
        if tender.method == Payment.CREDIT:
            continue
        _create_payment(order, tender, actor, paylink=paylink)
        if tender.method == Payment.STORE_CREDIT:
            ledger.redeem_store_credit(customer, tender.amount_htg, actor=actor,
                                       description=f"Vente {order.number}", order=order)
        _cash_movement_for(order, tender, actor, session)
    if credited > 0:
        Payment.objects.create(business=business, order=order, method=Payment.CREDIT, amount_htg=credited,
                               recorded_by=_staff(actor), recorded_by_name=_actor_name(actor))
        ledger.post_charge(customer, total, actor=actor, description=f"Vente {order.number}",
                           paid_amount_htg=money(total - credited), order=order, check_permission=False)

    for draft in drafts:
        if draft.product is not None and draft.stock_units:
            adjust_stock(draft.product.pk, -draft.stock_units, StockMovement.SALE, business=business, actor=actor,
                         reference_type="order", reference_id=order.number)

    order.status = _derive_status(order)
    if order.status == OrderStatus.COMPLETED:
        order.completed_at = timezone.now()
    order.save(update_fields=["status", "completed_at", "updated_at"])
    _record_status(order, "", actor)

    if customer is not None:
        Customer.objects.filter(pk=customer.pk).update(
            total_spent_htg=F("total_spent_htg") + total,
            total_purchases=F("total_purchases") + 1,
            last_purchase_at=timezone.now(),
        )
    if order.status == OrderStatus.CHECK_PENDING:
        from apps.notifications.services import notify

        notify(business, "check_pending", "Chèque à compenser", f"{order.number} — {order.client_name or 'Client'}",
               order_id=str(order.pk))
    audit(business, "order.created", actor=_staff(actor), target=order, total=str(total), status=order.status)
    return order, True


# --- Status ------------------------------------------------------------------

TRANSITIONS = {
    OrderStatus.PAID: {OrderStatus.READY, OrderStatus.PICKED_UP, OrderStatus.DELIVERED, OrderStatus.COMPLETED},
    OrderStatus.READY: {OrderStatus.PICKED_UP, OrderStatus.DELIVERED, OrderStatus.COMPLETED},
    OrderStatus.PARTIALLY_PAID: {OrderStatus.READY},
}


@transaction.atomic
def set_status(actor, order: Order, to_status: str, note: str = "") -> Order:
    order = Order.objects.select_for_update().get(pk=order.pk)
    if to_status == order.status:
        return order
    if to_status not in TRANSITIONS.get(order.status, set()):
        raise ApiError(f"Impossible de passer de « {order.get_status_display()} » à ce statut.", 409)
    if to_status == OrderStatus.PICKED_UP and order.fulfillment_mode != Fulfillment.PICKUP:
        raise ApiError("Seule une commande à retirer peut être marquée retirée.", 409)
    if to_status == OrderStatus.DELIVERED and order.fulfillment_mode != Fulfillment.DELIVERY:
        raise ApiError("Seule une commande à livrer peut être marquée livrée.", 409)
    if to_status in OrderStatus.TERMINAL and order.balance_due_htg > EPSILON:
        raise ApiError("Encaissez le solde avant de terminer la commande.", 409)
    previous = order.status
    order.status = to_status
    if to_status in OrderStatus.TERMINAL:
        order.completed_at = timezone.now()
    order.save(update_fields=["status", "completed_at", "updated_at"])
    _record_status(order, previous, actor, note)
    audit(order.business, "order.status", actor=_staff(actor), target=order, before=previous, after=to_status)
    return order


@transaction.atomic
def collect_payment(actor, order: Order, raw_payments, *, location=None, paylink=None) -> Order:
    """Collect what is still owed on a partially paid order."""
    order = Order.objects.select_for_update().get(pk=order.pk)
    if order.status in (OrderStatus.CANCELLED, OrderStatus.REFUNDED):
        raise ApiError("Cette commande est annulée.", 409)
    if order.balance_due_htg <= EPSILON:
        raise ApiError("Cette commande est déjà payée.", 409)
    tenders = parse_tenders(raw_payments, order.usd_rate)
    if not tenders:
        raise ApiError("Indiquez le paiement.")
    if any(t.method == Payment.CREDIT for t in tenders):
        raise ApiError("Le crédit ne peut pas payer un solde.")
    applied = money(sum((t.amount_htg for t in tenders), ZERO))
    if applied > order.balance_due_htg + EPSILON:
        raise ApiError(f"Le paiement dépasse le solde dû ({order.balance_due_htg} HTG).")
    session = _require_session(order.business, location or order.location, tenders)
    for tender in tenders:
        _create_payment(order, tender, actor, paylink=paylink)
        if tender.method == Payment.STORE_CREDIT:
            if order.customer is None:
                raise ApiError("Choisissez le client pour utiliser l'avoir.")
            ledger.redeem_store_credit(order.customer, tender.amount_htg, actor=actor,
                                       description=f"Solde {order.number}", order=order)
        _cash_movement_for(order, tender, actor, session, description=f"Solde {order.number}")
    if order.customer_id:
        customer = order.customer
        owed = min(applied, customer.balance_htg)
        if owed > 0:
            ledger.post_payment(customer, owed, actor=actor, method=tenders[0].method,
                                description=f"Solde {order.number}", order=order)
    order.amount_paid_htg = money(order.amount_paid_htg + applied)
    order.balance_due_htg = max(ZERO, money(order.balance_due_htg - applied))
    previous = order.status
    if previous in (OrderStatus.PARTIALLY_PAID, OrderStatus.CHECK_PENDING):
        order.status = _derive_status(order)
    order.save(update_fields=["amount_paid_htg", "balance_due_htg", "status", "updated_at"])
    if order.status != previous:
        _record_status(order, previous, actor, "Solde encaissé")
    audit(order.business, "order.collect", actor=_staff(actor), target=order, amount=str(applied))
    return order


# --- Checks ------------------------------------------------------------------


@transaction.atomic
def clear_check(actor, check: CheckPayment) -> CheckPayment:
    check = CheckPayment.objects.select_for_update().select_related("payment__order").get(pk=check.pk)
    if check.status != CheckPayment.PENDING:
        raise ApiError("Ce chèque a déjà été traité.", 409)
    check.status = CheckPayment.CLEARED
    check.cleared_at = timezone.now()
    check.cleared_by = _staff(actor)
    check.cleared_by_name = _actor_name(actor)
    check.save()
    Payment.objects.filter(pk=check.payment_id).update(status=Payment.CONFIRMED, updated_at=timezone.now())
    order = Order.objects.select_for_update().get(pk=check.payment.order_id)
    if order.status == OrderStatus.CHECK_PENDING:
        previous = order.status
        order.status = _derive_status(order)
        order.save(update_fields=["status", "updated_at"])
        _record_status(order, previous, actor, f"Chèque {check.number} compensé")
    audit(order.business, "check.cleared", actor=_staff(actor), target=check, order=order.number)
    return check


@transaction.atomic
def refuse_check(actor, check: CheckPayment, *, reason: str = "", charge_customer: bool = True) -> CheckPayment:
    """A bounced check reopens the balance and, when known, charges the client."""
    check = CheckPayment.objects.select_for_update().select_related("payment__order").get(pk=check.pk)
    if check.status != CheckPayment.PENDING:
        raise ApiError("Ce chèque a déjà été traité.", 409)
    check.status = CheckPayment.REFUSED
    check.refused_at = timezone.now()
    check.refused_reason = reason[:200]
    Payment.objects.filter(pk=check.payment_id).update(status=Payment.FAILED, updated_at=timezone.now())
    order = Order.objects.select_for_update().get(pk=check.payment.order_id)
    order.amount_paid_htg = max(ZERO, money(order.amount_paid_htg - check.amount_htg))
    order.balance_due_htg = money(order.balance_due_htg + check.amount_htg)
    customer = check.credit_customer or order.customer
    if charge_customer and customer is not None:
        ledger.post_charge(customer, check.amount_htg, actor=actor, description=f"Chèque refusé {check.number}",
                           order=order, enforce_limit=False)
        check.credit_posted = True
    check.save()
    previous = order.status
    if previous in (OrderStatus.CHECK_PENDING, OrderStatus.PAID, OrderStatus.COMPLETED, OrderStatus.READY):
        order.status = _derive_status(order)
    order.save(update_fields=["amount_paid_htg", "balance_due_htg", "status", "updated_at"])
    if order.status != previous:
        _record_status(order, previous, actor, f"Chèque {check.number} refusé")
    from apps.notifications.services import notify

    notify(order.business, "check_refused", "Chèque refusé",
           f"{check.number} — {check.payer_name} : {check.amount_htg} HTG", order_id=str(order.pk))
    audit(order.business, "check.refused", actor=_staff(actor), target=check, order=order.number)
    return check


# --- Refunds and cancellation ---------------------------------------------------


def _refundable_left(order: Order) -> Decimal:
    return max(ZERO, money(order.amount_paid_htg - order.refunded_htg))


@transaction.atomic
def refund(actor, order: Order, *, lines, method: str, reason: str, restock: bool = True, amount_htg=None,
           location=None) -> Refund:
    order = Order.objects.select_for_update().get(pk=order.pk)
    if order.status in (OrderStatus.CANCELLED, OrderStatus.REFUNDED, OrderStatus.CHECK_PENDING):
        raise ApiError("Cette commande ne peut pas être remboursée.", 409)
    if method not in dict(Refund.METHODS):
        raise ApiError("Mode de remboursement inconnu.")
    if not reason.strip():
        raise ApiError("Indiquez la raison du remboursement.")
    if not isinstance(lines, list) or not lines:
        raise ApiError("Choisissez les articles à rembourser.")
    by_id = {str(line.pk): line for line in order.lines.select_for_update()}
    factor = (order.total_htg - order.delivery_fee_htg) / order.subtotal_htg if order.subtotal_htg > 0 else Decimal(1)
    picked: list[tuple[OrderLine, int, Decimal]] = []
    for raw in lines:
        line = by_id.get(str((raw or {}).get("line_id") or ""))
        if line is None:
            raise ApiError("Article de commande introuvable.")
        qty = parse_quantity(raw.get("quantity"))
        if qty > line.quantity - line.refunded_quantity:
            raise ApiError(f"Quantité à rembourser trop grande pour {line.product_name}.")
        picked.append((line, qty, money(line.unit_price_htg * qty * factor)))
    computed = money(sum((amount for _, _, amount in picked), ZERO))
    amount = money(amount_htg) if amount_htg not in (None, "") else computed
    if amount <= 0:
        raise ApiError("Montant invalide.")
    ceiling = _refundable_left(order) if method != "credit" else order.balance_due_htg
    if amount > ceiling + EPSILON:
        raise ApiError(f"Le remboursement dépasse le montant disponible ({ceiling} HTG).")
    if method in ("storeCredit", "credit") and order.customer is None:
        raise ApiError("Choisissez le client de la commande.")

    record = Refund.objects.create(
        business=order.business, order=order, number=next_number(order.business, "RMB"), amount_htg=amount,
        method=method, reason=reason[:300], restock=restock, recorded_by=_staff(actor),
        recorded_by_name=_actor_name(actor),
    )
    RefundLine.objects.bulk_create([RefundLine(refund=record, order_line=line, quantity=qty, amount_htg=value)
                                    for line, qty, value in picked])
    for line, qty, _ in picked:
        OrderLine.objects.filter(pk=line.pk).update(refunded_quantity=F("refunded_quantity") + qty)
        if restock and line.product_id and line.stock_units:
            each = line.stock_units // max(1, line.quantity)
            adjust_stock(line.product_id, each * qty, StockMovement.RETURN, business=order.business, actor=actor,
                         reference_type="refund", reference_id=record.number)

    if method == "storeCredit":
        ledger.issue_store_credit(order.customer, amount, actor=actor, description=f"Remboursement {order.number}",
                                  order=order)
    elif method == "credit":
        ledger.post_adjustment(order.customer, -amount, actor=actor, description=f"Remboursement {order.number}")
        order.balance_due_htg = max(ZERO, money(order.balance_due_htg - amount))
    else:
        session = open_session_for(location or order.location)
        if session is None and TENDER_FOR_METHOD.get(method) in CashMovement.DRAWER_TENDERS:
            raise ApiError("Ouvrez la caisse pour rembourser en espèces.", 409)
        tender = TenderDraft(method, amount, ZERO, ZERO, ZERO, record.number, "", None)
        _cash_movement_for(order, tender, actor, session, out=True, description=f"Remboursement {order.number}")
    if method != "credit":
        order.refunded_htg = money(order.refunded_htg + amount)
    fully_returned = not order.lines.exclude(refunded_quantity__gte=F("quantity")).exists()
    previous = order.status
    if fully_returned:
        order.status = OrderStatus.REFUNDED
    order.save(update_fields=["refunded_htg", "balance_due_htg", "status", "updated_at"])
    if order.status != previous:
        _record_status(order, previous, actor, reason)
    audit(order.business, "order.refund", actor=_staff(actor), target=order, amount=str(amount), method=method)
    return record


@transaction.atomic
def cancel(actor, order: Order, *, reason: str, restock: bool = True) -> Order:
    order = Order.objects.select_for_update().get(pk=order.pk)
    if order.status in OrderStatus.TERMINAL:
        raise ApiError("Cette commande est déjà terminée.", 409)
    if not reason.strip():
        raise ApiError("Indiquez la raison de l'annulation.")
    collected = order.payments.filter(status__in=[Payment.CONFIRMED, Payment.PENDING]).exclude(method=Payment.CREDIT)
    if collected.exists() and _refundable_left(order) > EPSILON:
        raise ApiError("Remboursez d'abord les paiements reçus.", 409)
    if order.customer_id and order.balance_due_htg > 0:
        owed = min(order.balance_due_htg, order.customer.balance_htg)
        if owed > 0:
            ledger.post_adjustment(order.customer, -owed, actor=actor, description=f"Annulation {order.number}")
    if restock:
        for line in order.lines.all():
            remaining = line.quantity - line.refunded_quantity
            if line.product_id and line.stock_units and remaining > 0:
                each = line.stock_units // max(1, line.quantity)
                adjust_stock(line.product_id, each * remaining, StockMovement.RETURN, business=order.business,
                             actor=actor, reference_type="cancel", reference_id=order.number)
    previous = order.status
    order.status = OrderStatus.CANCELLED
    order.balance_due_htg = ZERO
    order.cancelled_at = timezone.now()
    order.cancel_reason = reason[:200]
    order.save(update_fields=["status", "balance_due_htg", "cancelled_at", "cancel_reason", "updated_at"])
    _record_status(order, previous, actor, reason)
    audit(order.business, "order.cancelled", actor=_staff(actor), target=order, reason=reason[:200])
    return order


# --- Quotes ------------------------------------------------------------------


@transaction.atomic
def save_quote(actor, data: dict, *, quote: Quote | None = None, location=None, source: str = OrderSource.POS) -> Quote:
    business = actor.business
    drafts = build_lines(business, data.get("lines"), actor)
    customer = _customer(business, data.get("customer_id") or data.get("customer"))
    mode = str(data.get("fulfillment_mode") or Fulfillment.IN_STORE)
    _validate_fulfillment(business, mode, data)
    discount_percent = money(data.get("discount_percent"))
    if discount_percent < 0 or discount_percent > 100:
        raise ApiError("Remise invalide.")
    delivery_fee = money(data.get("delivery_fee_htg")) if mode == Fulfillment.DELIVERY else ZERO
    totals = compute_totals(sum((d.line_total for d in drafts), ZERO), discount_percent=discount_percent,
                            delivery_fee=delivery_fee)
    fields = dict(
        customer=customer,
        client_name=str(data.get("client_name") or (customer.name if customer else ""))[:120],
        client_phone=str(data.get("client_phone") or (customer.phone if customer else ""))[:40],
        client_email=str(data.get("client_email") or "")[:254],
        fulfillment_mode=mode,
        delivery_location=str(data.get("delivery_location") or "")[:300],
        delivery_phone=str(data.get("delivery_phone") or "")[:40],
        delivery_fee_htg=delivery_fee,
        discount_percent=discount_percent,
        subtotal_htg=totals.subtotal,
        total_htg=totals.total,
        note=str(data.get("note") or "")[:500],
        valid_until=parse_date(str(data.get("valid_until") or "")) if data.get("valid_until") else None,
    )
    if quote is None:
        quote_id = _parse_uuid(data.get("id")) or uuid.uuid4()
        existing = Quote.objects.filter(pk=quote_id).first()
        if existing is not None:
            if existing.business_id != business.pk:
                raise ApiError("Identifiant de devis déjà utilisé.", 409)
            quote = existing
    if quote is None:
        quote = Quote.objects.create(id=quote_id, business=business, number=next_number(business, "DEV"),
                                     source=source, location=location, created_by=_staff(actor),
                                     created_by_name=_actor_name(actor), **fields)
    else:
        if quote.status != QuoteStatus.DRAFT:
            raise ApiError("Ce devis ne peut plus être modifié.", 409)
        for key, value in fields.items():
            setattr(quote, key, value)
        quote.save()
        quote.lines.all().delete()
    QuoteLine.objects.bulk_create([
        QuoteLine(quote=quote, product=d.product, product_name=d.name, options_label=d.options_label[:300],
                  choices=[o["id"] for o in d.options], measure=d.measure, width=d.width, quantity=d.quantity,
                  unit_price_htg=d.unit_price, line_total_htg=d.line_total, sort_order=index)
        for index, d in enumerate(drafts)
    ])
    return quote


def quote_sale_payload(quote: Quote) -> dict:
    return {
        "customer_id": str(quote.customer_id) if quote.customer_id else None,
        "client_name": quote.client_name,
        "client_phone": quote.client_phone,
        "client_email": quote.client_email,
        "fulfillment_mode": quote.fulfillment_mode,
        "delivery_location": quote.delivery_location,
        "delivery_phone": quote.delivery_phone,
        "delivery_fee_htg": quote.delivery_fee_htg,
        "lines": [
            {"product_id": str(line.product_id) if line.product_id else None, "name": line.product_name,
             "quantity": line.quantity, "measure": line.measure, "width": line.width, "choices": line.choices,
             **({"unit_price_htg": line.unit_price_htg} if line.product_id is None else {})}
            for line in quote.lines.all()
        ],
    }


@transaction.atomic
def convert_quote(actor, quote: Quote, data: dict, *, location=None, device=None) -> Order:
    quote = Quote.objects.select_for_update().get(pk=quote.pk)
    if quote.status != QuoteStatus.DRAFT:
        raise ApiError("Ce devis a déjà été traité.", 409)
    payload = {**quote_sale_payload(quote), "discount_percent": quote.discount_percent, **data}
    order, _ = create_sale(actor, payload, location=location or quote.location, device=device, source=quote.source,
                           discount_preapproved="discount_percent" not in data)
    order.from_quote = quote
    order.save(update_fields=["from_quote", "updated_at"])
    quote.status = QuoteStatus.CONVERTED
    quote.converted_order = order
    quote.save(update_fields=["status", "converted_order", "updated_at"])
    return order

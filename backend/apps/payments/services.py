from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.common.actors import SystemActor
from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.money import EPSILON, htg_to_usd_cents, money
from apps.common.numbering import next_number

from .models import Payment, PayLink, WebhookEvent
from .providers import stripe
from .providers.errors import PaymentError

MAX_LINK_HOURS = 24 * 30


def public_origin(request=None) -> str:
    if settings.PUBLIC_BASE_URL:
        return settings.PUBLIC_BASE_URL
    if request is not None:
        return request.build_absolute_uri("/").rstrip("/")
    return "http://localhost:8000"


def _customer(business, raw_id):
    if not raw_id:
        return None
    from apps.customers.models import Customer

    customer = Customer.objects.filter(business=business, pk=raw_id).first()
    if customer is None:
        raise ApiError("Client introuvable.", 404)
    return customer


def _order(business, raw_id):
    if not raw_id:
        return None
    from apps.sales.models import Order

    order = Order.objects.filter(business=business, pk=raw_id).first()
    if order is None:
        raise ApiError("Commande introuvable.", 404)
    return order


def create_paylink(actor, data: dict, *, request=None) -> PayLink:
    business = actor.business
    order = _order(business, data.get("order_id") or data.get("order"))
    customer = _customer(business, data.get("customer_id") or data.get("customer")) or (order.customer if order else None)
    amount = money(data.get("amount_htg"))
    if order is not None and amount <= 0:
        amount = order.balance_due_htg
    if amount <= 0:
        raise ApiError("Le montant doit être supérieur à zéro.")
    if order is not None and amount > order.balance_due_htg + EPSILON:
        raise ApiError(f"Le montant dépasse le solde dû ({order.balance_due_htg} HTG).")
    if order is None and customer is None:
        raise ApiError("Choisissez le client qui recevra l'avoir.")
    rate = business.settings.effective_usd_rate()
    usd_cents = htg_to_usd_cents(amount, rate)
    if usd_cents < stripe.MIN_CARD_CENTS:
        raise ApiError("Le montant est trop petit pour un paiement par carte.")
    try:
        hours = int(data.get("expires_in_hours") or 72)
    except (TypeError, ValueError):
        hours = 72
    hours = max(1, min(hours, MAX_LINK_HOURS))
    channel = str(data.get("channel") or "whatsApp")
    if channel not in dict(PayLink.CHANNELS):
        channel = "whatsApp"
    link = PayLink(
        business=business,
        reference=next_number(business, "LNK"),
        customer=customer,
        customer_name=str(data.get("customer_name") or (customer.name if customer else order.client_name if order else ""))[:120],
        customer_phone=str(data.get("customer_phone") or (customer.phone if customer else ""))[:40],
        payer_email=str(data.get("payer_email") or (customer.email if customer else ""))[:254],
        amount_htg=amount,
        usd_rate=rate,
        order_usd_cents=usd_cents,
        channel=channel,
        source="orderBill" if order else "standalone",
        sent_to=str(data.get("sent_to") or "")[:120],
        order=order,
        note=str(data.get("note") or "")[:300],
        expires_at=timezone.now() + timedelta(hours=hours),
        created_by=actor if getattr(actor, "pk", None) else None,
        created_by_name=getattr(actor, "full_name", ""),
    )
    checkout = stripe.create_checkout(
        reference=link.reference,
        order_usd_cents=usd_cents,
        description=f"{business.name} · {link.reference}",
        recipient_name=link.customer_name,
        recipient_email=link.payer_email,
        recipient_phone=link.customer_phone,
        origin=public_origin(request),
        kind="paylink",
        metadata={"business": str(business.pk), "paylink": str(link.pk)},
    )
    link.payment_url = checkout["url"]
    link.stripe_session_id = checkout["id"]
    link.payer_total_usd_cents = checkout["total_usd_cents"]
    link.platform_fee_usd_cents = checkout["platform_fee_usd_cents"]
    link.stripe_fee_usd_cents = checkout["stripe_fee_usd_cents"]
    link.save()
    audit(business, "paylink.created", actor=actor, target=link, amount=str(amount))
    return link


def expire_if_due(link: PayLink) -> PayLink:
    if link.status == PayLink.ACTIVE and link.expires_at and link.expires_at < timezone.now():
        link.status = PayLink.INACTIVE
        link.save(update_fields=["status", "updated_at"])
    return link


@transaction.atomic
def settle_paylink(link: PayLink, *, transaction_id: str = "", last4: str = "", method: str = "card",
                   received_usd_cents: int | None = None) -> PayLink:
    """Idempotent. Pays the linked order's balance, else credits the client."""
    link = PayLink.objects.select_for_update().get(pk=link.pk)
    if link.paid_at is not None:
        return link
    if received_usd_cents is not None and link.payer_total_usd_cents and received_usd_cents < link.payer_total_usd_cents:
        raise PaymentError(402, "Le montant reçu ne correspond pas au lien.")
    actor = SystemActor(link.business, "Lien de paiement")
    link.status = PayLink.PAID
    link.paid_at = timezone.now()
    link.payment_transaction_id = transaction_id[:120]
    link.payment_last4 = last4[:4]
    link.payment_method = method[:20]
    link.save()
    remaining = link.amount_htg
    if link.order_id:
        from apps.sales.services import collect_payment

        order = link.order
        applied = min(remaining, order.balance_due_htg)
        if applied > EPSILON:
            collect_payment(actor, order, [{"method": Payment.PAYMENT_LINK, "amount_htg": applied,
                                            "reference": link.reference, "last_four": last4}], paylink=link)
            remaining = money(remaining - applied)
    if remaining > EPSILON and link.customer_id:
        from apps.customers.ledger import issue_store_credit

        issue_store_credit(link.customer, remaining, actor=actor, description=f"Lien {link.reference}", paylink=link)
    from apps.notifications.services import notify

    notify(link.business, "paylink_paid", "Lien payé",
           f"{link.reference} — {link.customer_name or 'Client'} : {link.amount_htg} HTG", paylink_id=str(link.pk))
    audit(link.business, "paylink.paid", target=link, transaction=transaction_id)
    return link


def refresh_paylink(link: PayLink) -> PayLink:
    expire_if_due(link)
    if link.paid_at or not link.stripe_session_id or not stripe.configured():
        return link
    session = stripe.fetch_checkout(link.stripe_session_id)
    if str(session.get("payment_status") or "") == "paid":
        return settle_paylink(link, transaction_id=str(session.get("payment_intent") or ""),
                              received_usd_cents=int(session.get("amount_total") or 0) or None)
    return link


def cancel_paylink(actor, link: PayLink) -> PayLink:
    if link.paid_at is not None:
        raise ApiError("Ce lien est déjà payé.", 409)
    link.status = PayLink.INACTIVE
    link.canceled_at = timezone.now()
    link.canceled_by = getattr(actor, "full_name", "")[:120]
    link.save(update_fields=["status", "canceled_at", "canceled_by", "updated_at"])
    if link.stripe_session_id and stripe.configured():
        try:
            stripe.request("POST", f"/checkout/sessions/{link.stripe_session_id}/expire")
        except PaymentError:
            pass
    audit(link.business, "paylink.cancelled", actor=actor, target=link)
    return link


def _first_time(provider: str, event_id: str, kind: str) -> bool:
    if not event_id:
        return True
    try:
        with transaction.atomic():
            WebhookEvent.objects.create(provider=provider, event_id=event_id[:120], kind=kind[:80])
    except IntegrityError:
        return False
    return True


def handle_stripe_event(event: dict) -> dict:
    kind = str(event.get("type") or "")
    obj = ((event.get("data") or {}).get("object") or {}) if isinstance(event, dict) else {}
    metadata = obj.get("metadata") or {}
    purpose = str(metadata.get("kind") or "")
    if not _first_time("stripe", str(event.get("id") or ""), kind):
        return {"received": True, "duplicate": True}

    if kind == "payment_intent.succeeded" and purpose == "storefront":
        from apps.storefront.services import settle_card_intent

        try:
            paid = settle_card_intent(str(metadata.get("reference") or ""), obj)
        except ApiError:
            paid = False
        return {"received": True, "paid": paid}

    accepted = kind in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}
    paid = accepted and str(obj.get("payment_status") or "") not in {"", "unpaid"}
    if paid and purpose == "paylink":
        link = PayLink.objects.filter(pk=metadata.get("paylink") or None,
                                      stripe_session_id=str(obj.get("id") or "")).first()
        if link is not None:
            settle_paylink(link, transaction_id=str(obj.get("payment_intent") or ""),
                           received_usd_cents=int(obj.get("amount_total") or 0) or None)
    return {"received": True, "paid": paid}

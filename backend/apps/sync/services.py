"""Offline sync.

push: the register replays its queue in order. Each operation runs in its
own transaction and is recorded by op_id, so a batch resent after a dropped
connection is answered from the log instead of applied twice.

pull: rows changed since the last pull, plus tombstones for deletions.
"""

from __future__ import annotations

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import ValidationError

from apps.accounts import roles
from apps.accounts.models import ExchangeRate, StaffMember
from apps.accounts.serializers import BusinessSettingsSerializer, StaffRosterSerializer
from apps.catalog.models import Category, Product, Supplier
from apps.catalog.serializers import CategorySerializer, ProductSerializer, SupplierSerializer
from apps.common.exceptions import ApiError
from apps.customers.models import Customer
from apps.customers.serializers import CustomerSerializer
from apps.sales.models import Order, Quote
from apps.sales.serializers import OrderSerializer, QuoteSerializer

from .models import SyncOperation, Tombstone

MAX_BATCH = 100
PULL_LIMIT = 500
FIRST_PULL_ORDER_DAYS = 30

PERMISSIONS = {
    "sale": roles.TRANSACTIONS_OPERATE,
    "orderStatus": roles.TRANSACTIONS_OPERATE,
    "orderPayment": roles.TRANSACTIONS_OPERATE,
    "quote": roles.TRANSACTIONS_OPERATE,
    "customer": roles.TRANSACTIONS_OPERATE,
    "customerAccount": roles.TRANSACTIONS_OPERATE,
    "product": roles.CATALOG_MANAGE,
    "supplier": roles.CATALOG_MANAGE,
    "stock": roles.CATALOG_MANAGE,
    "cashMovement": roles.FINANCIAL_CASH,
}


def _upsert(serializer_class, model, business, payload: dict, context: dict):
    instance = model.objects.filter(business=business, pk=payload.get("id")).first() if payload.get("id") else None
    serializer = serializer_class(instance, data=payload, partial=instance is not None, context=context)
    serializer.is_valid(raise_exception=True)
    obj = serializer.save(business=business) if instance is None else serializer.save()
    return {"id": str(obj.pk)}


def _order(business, raw_id) -> Order:
    order = Order.objects.filter(business=business, pk=raw_id).first() if raw_id else None
    if order is None:
        raise ApiError("Commande introuvable.", 404)
    return order


def _apply(kind: str, payload: dict, *, staff: StaffMember, location, device) -> dict:
    from apps.sales import services as sales

    business = staff.business
    context = {"business": business, "request": None}
    if kind == "sale":
        order, created = sales.create_sale(staff, payload, location=location, device=device)
        return {"id": str(order.pk), "number": order.number, "status": order.status, "created": created}
    if kind == "orderStatus":
        order = sales.set_status(staff, _order(business, payload.get("order_id")), str(payload.get("status") or ""),
                                 str(payload.get("note") or ""))
        return {"id": str(order.pk), "status": order.status}
    if kind == "orderPayment":
        order = sales.collect_payment(staff, _order(business, payload.get("order_id")), payload.get("payments"),
                                      location=location)
        return {"id": str(order.pk), "status": order.status, "balance_due_htg": str(order.balance_due_htg)}
    if kind == "quote":
        existing = Quote.objects.filter(business=business, pk=payload.get("id")).first() if payload.get("id") else None
        quote = sales.save_quote(staff, payload, quote=existing, location=location)
        return {"id": str(quote.pk), "number": quote.number}
    if kind == "product":
        return _upsert(ProductSerializer, Product, business, payload, context)
    if kind == "supplier":
        return _upsert(SupplierSerializer, Supplier, business, payload, context)
    if kind == "customer":
        return _upsert(CustomerSerializer, Customer, business, payload, context)
    if kind == "customerAccount":
        from apps.cash.services import record_customer_payment
        from apps.customers import ledger

        customer = Customer.objects.filter(business=business, pk=payload.get("customer_id")).first()
        if customer is None:
            raise ApiError("Client introuvable.", 404)
        if payload.get("type") != "payment":
            raise ApiError("Seuls les paiements de compte se synchronisent hors ligne.")
        if not staff.has_perm_code(roles.FINANCIAL_CASH):
            raise ApiError("Vous n'avez pas l'autorisation d'encaisser un paiement de compte.", 403)
        method = str(payload.get("method") or "cash")
        entry = ledger.post_payment(customer, payload.get("amount_htg"), actor=staff, method=method)
        record_customer_payment(staff, entry, method, payload.get("amount_usd"), location=location)
        return {"id": str(entry.pk), "receipt_number": entry.receipt_number}
    if kind == "stock":
        from apps.catalog.services import manual_stock_change

        product = Product.objects.filter(business=business, pk=payload.get("product_id")).first()
        if product is None:
            raise ApiError("Article introuvable.", 404)
        movement = manual_stock_change(product, kind=str(payload.get("kind") or ""),
                                       quantity=int(payload.get("quantity") or 0), actor=staff,
                                       note=str(payload.get("note") or ""))
        return {"id": str(movement.pk) if movement else None}
    if kind == "cashMovement":
        from apps.cash.services import add_movement, open_session_for

        session = open_session_for(location)
        if session is None:
            raise ApiError("Aucune caisse ouverte.", 409)
        movement = add_movement(staff, session, type=str(payload.get("type") or ""),
                                tender=str(payload.get("tender") or "cashHtg"), amount_htg=payload.get("amount_htg"),
                                amount_usd=payload.get("amount_usd"), description=str(payload.get("description") or ""))
        return {"id": str(movement.pk)}
    raise ApiError("Type d'opération inconnu.")


def _error_message(exc: Exception) -> str:
    if isinstance(exc, ApiError):
        return exc.message
    if isinstance(exc, ValidationError):
        detail = exc.detail
        if isinstance(detail, dict):
            first = next(iter(detail.values()), "")
            detail = first[0] if isinstance(first, list) and first else first
        elif isinstance(detail, list) and detail:
            detail = detail[0]
        return str(detail)[:300] or "Données invalides."
    return "Opération refusée."


def push(staff: StaffMember, operations, *, location=None, device=None) -> list[dict]:
    if not isinstance(operations, list):
        raise ApiError("Liste d'opérations attendue.")
    if len(operations) > MAX_BATCH:
        raise ApiError(f"{MAX_BATCH} opérations au maximum par envoi.")
    business = staff.business
    results = []
    for raw in operations:
        if not isinstance(raw, dict):
            results.append({"op_id": None, "status": SyncOperation.FAILED, "error": "Opération invalide."})
            continue
        op_id = str(raw.get("op_id") or "").strip()[:64]
        kind = str(raw.get("kind") or "")
        if not op_id:
            results.append({"op_id": None, "status": SyncOperation.FAILED, "error": "op_id manquant."})
            continue
        done = SyncOperation.objects.filter(business=business, op_id=op_id).first()
        if done is not None:
            results.append({"op_id": op_id, "status": done.status, "result": done.result, "error": done.error,
                            "replayed": True})
            continue
        status, result, error = SyncOperation.APPLIED, {}, ""
        code = PERMISSIONS.get(kind)
        try:
            if code and not staff.has_perm_code(code):
                raise ApiError("Vous n'avez pas l'autorisation pour cette opération.", 403)
            with transaction.atomic():
                result = _apply(kind, raw.get("payload") or {}, staff=staff, location=location, device=device)
        except (ApiError, ValidationError) as exc:
            status, error = SyncOperation.FAILED, _error_message(exc)
        try:
            with transaction.atomic():
                SyncOperation.objects.create(
                    business=business, op_id=op_id, kind=kind[:30], device=device, staff=staff, status=status,
                    result=result, error=error[:300],
                    client_created_at=parse_datetime(str(raw.get("created_at") or "")) if raw.get("created_at") else None,
                )
        except IntegrityError:
            pass
        results.append({"op_id": op_id, "status": status, "result": result, "error": error})
    return results


def pull(staff: StaffMember, since_raw: str | None) -> dict:
    business = staff.business
    started = timezone.now()
    since = parse_datetime(since_raw) if since_raw else None
    if since_raw and since is None:
        raise ApiError("Date « since » invalide.")
    first = since is None

    def changed(qs):
        return qs.filter(updated_at__gt=since) if since else qs

    context = {"business": business, "request": None}
    products = list(changed(Product.objects.filter(business=business)).select_related("category")
                    .prefetch_related("option_groups__choices").order_by("updated_at")[:PULL_LIMIT + 1])
    customers = list(changed(Customer.objects.filter(business=business)).order_by("updated_at")[:PULL_LIMIT + 1])
    orders_qs = Order.objects.filter(business=business)
    if first:
        orders_qs = orders_qs.filter(created_at__gte=started - timedelta(days=FIRST_PULL_ORDER_DAYS))
    orders = list(changed(orders_qs).prefetch_related("lines", "payments__check_details", "status_events",
                                                      "refunds__lines").order_by("updated_at")[:PULL_LIMIT + 1])
    quotes = list(changed(Quote.objects.filter(business=business)).prefetch_related("lines")
                  .order_by("updated_at")[:PULL_LIMIT + 1])
    has_more = any(len(rows) > PULL_LIMIT for rows in (products, customers, orders, quotes))
    # When a page is cut, continue from the oldest last-row so nothing is skipped.
    cut_points = [rows[PULL_LIMIT - 1].updated_at for rows in (products, customers, orders, quotes)
                  if len(rows) > PULL_LIMIT]
    next_since = min(cut_points) - timedelta(microseconds=1) if cut_points else started
    tombstones = Tombstone.objects.filter(business=business)
    if since:
        tombstones = tombstones.filter(created_at__gt=since)
    rate = ExchangeRate.objects.filter(business=business).order_by("-effective_at").first()
    return {
        "server_time": started,
        "next_since": next_since,
        "has_more": has_more,
        "settings": BusinessSettingsSerializer(business.settings, context=context).data,
        "usd_rate": business.settings.effective_usd_rate(),
        "usd_rate_set_at": rate.effective_at if rate else None,
        "categories": CategorySerializer(changed(Category.objects.filter(business=business)), many=True).data,
        "suppliers": SupplierSerializer(changed(Supplier.objects.filter(business=business)).prefetch_related("contacts"),
                                        many=True, context=context).data,
        "staff": StaffRosterSerializer(StaffMember.objects.filter(business=business, is_active=True), many=True).data,
        "products": ProductSerializer(products[:PULL_LIMIT], many=True, context=context).data,
        "customers": CustomerSerializer(customers[:PULL_LIMIT], many=True, context=context).data,
        "orders": OrderSerializer(orders[:PULL_LIMIT], many=True).data,
        "quotes": QuoteSerializer(quotes[:PULL_LIMIT], many=True).data,
        "deleted": [{"entity": t.entity, "id": t.object_id} for t in tombstones[:2000]],
    }

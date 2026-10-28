"""Read-only aggregates. Every query is bounded by business and date range."""

from __future__ import annotations

from datetime import date, timedelta

from django.db.models import Count, DecimalField, ExpressionWrapper, F, Q, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from apps.cash.models import CashSession
from apps.catalog.models import Product
from apps.common.money import ZERO, money
from apps.customers.models import Customer, CustomerTransaction
from apps.payments.models import CheckPayment, Payment
from apps.sales.models import Order, OrderLine, OrderStatus

EXCLUDED = (OrderStatus.CANCELLED,)


def period_orders(business, start: date, end: date, location=None):
    qs = Order.objects.filter(business=business, created_at__date__gte=start, created_at__date__lte=end)
    if location:
        qs = qs.filter(location=location)
    return qs.exclude(status__in=EXCLUDED)


def _sum(qs, field: str):
    return money(qs.aggregate(v=Sum(field))["v"] or 0)


def summary(business, start: date, end: date, location=None) -> dict:
    orders = period_orders(business, start, end, location)
    totals = orders.aggregate(
        count=Count("id"), gross=Sum("total_htg"), subtotal=Sum("subtotal_htg"), discount=Sum("discount_htg"),
        tax=Sum("tax_htg"), service=Sum("service_charge_htg"), delivery=Sum("delivery_fee_htg"),
        refunded=Sum("refunded_htg"), due=Sum("balance_due_htg"),
    )
    lines = OrderLine.objects.filter(order__in=orders)
    cost = lines.aggregate(v=Sum(ExpressionWrapper(F("unit_cost_htg") * F("quantity"),
                                                   output_field=DecimalField(max_digits=16, decimal_places=2))))["v"]
    count = totals["count"] or 0
    gross = money(totals["gross"] or 0)
    refunded = money(totals["refunded"] or 0)
    net = money(gross - refunded)
    return {
        "from": start, "to": end,
        "orders": count,
        "gross_htg": gross,
        "subtotal_htg": money(totals["subtotal"] or 0),
        "discount_htg": money(totals["discount"] or 0),
        "tax_htg": money(totals["tax"] or 0),
        "service_charge_htg": money(totals["service"] or 0),
        "delivery_fee_htg": money(totals["delivery"] or 0),
        "refunded_htg": refunded,
        "net_htg": net,
        "balance_due_htg": money(totals["due"] or 0),
        "average_ticket_htg": money(gross / count) if count else ZERO,
        "items_sold": lines.aggregate(v=Sum("quantity"))["v"] or 0,
        "cost_htg": money(cost or 0),
        "margin_htg": money(net - money(cost or 0)),
        "by_payment_method": payment_methods(business, start, end, location),
        "by_status": list(orders.values("status").annotate(count=Count("id"), total_htg=Sum("total_htg"))
                          .order_by("status")),
    }


def sales_by_day(business, start: date, end: date, location=None) -> list[dict]:
    rows = (period_orders(business, start, end, location).annotate(day=TruncDate("created_at"))
            .values("day").annotate(orders=Count("id"), total_htg=Sum("total_htg"), refunded_htg=Sum("refunded_htg"))
            .order_by("day"))
    by_day = {row["day"]: row for row in rows}
    out = []
    day = start
    while day <= end:
        row = by_day.get(day) or {}
        out.append({"day": day, "orders": row.get("orders", 0), "total_htg": money(row.get("total_htg") or 0),
                    "refunded_htg": money(row.get("refunded_htg") or 0)})
        day += timedelta(days=1)
    return out


def payment_methods(business, start: date, end: date, location=None) -> list[dict]:
    payments = Payment.objects.filter(order__in=period_orders(business, start, end, location),
                                      status__in=[Payment.CONFIRMED, Payment.PENDING])
    return [
        {"method": row["method"], "count": row["count"], "amount_htg": money(row["amount"] or 0),
         "amount_usd": money(row["usd"] or 0)}
        for row in payments.values("method").annotate(count=Count("id"), amount=Sum("amount_htg"), usd=Sum("amount_usd"))
        .order_by("-amount")
    ]


def cashiers(business, start: date, end: date, location=None) -> list[dict]:
    rows = (period_orders(business, start, end, location).values("recorded_by", "recorded_by_name")
            .annotate(orders=Count("id"), total_htg=Sum("total_htg"), refunded_htg=Sum("refunded_htg"))
            .order_by("-total_htg"))
    return [{**row, "total_htg": money(row["total_htg"] or 0), "refunded_htg": money(row["refunded_htg"] or 0)}
            for row in rows]


def top_products(business, start: date, end: date, *, limit: int = 20, location=None) -> list[dict]:
    rows = (OrderLine.objects.filter(order__in=period_orders(business, start, end, location))
            .values("product", "product_name")
            .annotate(quantity=Sum("quantity"), revenue_htg=Sum("line_total_htg"),
                      cost_htg=Sum(ExpressionWrapper(F("unit_cost_htg") * F("quantity"),
                                                     output_field=DecimalField(max_digits=16, decimal_places=2))))
            .order_by("-revenue_htg")[:limit])
    return [{**row, "revenue_htg": money(row["revenue_htg"] or 0), "cost_htg": money(row["cost_htg"] or 0)}
            for row in rows]


def stock_value(business) -> dict:
    products = Product.objects.filter(business=business, is_active=True, track_stock=True)
    positive = products.filter(stock_quantity__gt=0)
    value_expr = ExpressionWrapper(F("stock_quantity") * F("cost_htg"), output_field=DecimalField(max_digits=18, decimal_places=2))
    retail_expr = ExpressionWrapper(F("stock_quantity") * F("price_htg"), output_field=DecimalField(max_digits=18, decimal_places=2))
    totals = positive.aggregate(cost=Sum(value_expr), retail=Sum(retail_expr), units=Sum("stock_quantity"))
    return {
        "products": products.count(),
        "units": totals["units"] or 0,
        "cost_value_htg": money(totals["cost"] or 0),
        "retail_value_htg": money(totals["retail"] or 0),
        "low_stock": products.filter(stock_quantity__lte=F("min_stock")).count(),
        "out_of_stock": products.filter(stock_quantity__lte=0).count(),
        "negative_stock": products.filter(stock_quantity__lt=0).count(),
    }


def receivables(business) -> dict:
    """Client balances aged by the oldest charge still unpaid (FIFO)."""
    today = timezone.localdate()
    buckets = {"0_30": ZERO, "31_60": ZERO, "61_90": ZERO, "90_plus": ZERO}
    rows = []
    customers = Customer.objects.filter(business=business, balance_htg__gt=0).order_by("-balance_htg")
    charges = (CustomerTransaction.objects.filter(customer__in=customers, kind=CustomerTransaction.CHARGE)
               .order_by("customer_id", "-created_at").values("customer_id", "amount_htg", "paid_amount_htg", "created_at"))
    by_customer: dict = {}
    for charge in charges:
        by_customer.setdefault(charge["customer_id"], []).append(charge)
    for customer in customers:
        remaining = customer.balance_htg
        oldest = None
        for charge in by_customer.get(customer.pk, []):
            if remaining <= 0:
                break
            credited = money(charge["amount_htg"] - charge["paid_amount_htg"])
            if credited <= 0:
                continue
            portion = min(remaining, credited)
            age = (today - timezone.localtime(charge["created_at"]).date()).days
            key = "0_30" if age <= 30 else "31_60" if age <= 60 else "61_90" if age <= 90 else "90_plus"
            buckets[key] = money(buckets[key] + portion)
            remaining = money(remaining - portion)
            oldest = age
        if remaining > 0:
            buckets["90_plus"] = money(buckets["90_plus"] + remaining)
        rows.append({"customer": str(customer.pk), "name": customer.name, "phone": customer.phone,
                     "balance_htg": customer.balance_htg, "credit_limit_htg": customer.credit_limit_htg,
                     "oldest_days": oldest, "is_credit_blocked": customer.is_credit_blocked})
    return {"total_htg": money(sum(buckets.values(), ZERO)), "buckets": buckets, "customers": rows}


def cash_variances(business, start: date, end: date) -> list[dict]:
    sessions = (CashSession.objects.filter(business=business, status=CashSession.CLOSED, closed_at__date__gte=start,
                                           closed_at__date__lte=end)
                .exclude(over_short_htg=0, over_short_usd=0).select_related("location").order_by("-closed_at"))
    return [{"session": str(s.pk), "location": s.location.name, "opened_by": s.opened_by_name,
             "closed_by": s.closed_by_name, "closed_at": s.closed_at, "expected_htg": s.expected_htg,
             "counted_htg": s.counted_htg, "over_short_htg": s.over_short_htg, "expected_usd": s.expected_usd,
             "counted_usd": s.counted_usd, "over_short_usd": s.over_short_usd} for s in sessions]


def dashboard(business, location=None) -> dict:
    from apps.notifications.models import Notification

    today = timezone.localdate()
    orders_today = period_orders(business, today, today, location)
    open_statuses = [OrderStatus.PAID, OrderStatus.READY, OrderStatus.PARTIALLY_PAID, OrderStatus.CHECK_PENDING]
    open_orders = Order.objects.filter(business=business, status__in=open_statuses)
    session = CashSession.objects.filter(business=business, status=CashSession.OPEN)
    if location:
        session = session.filter(location=location)
    return {
        "today": today,
        "sales_today_htg": _sum(orders_today, "total_htg"),
        "orders_today": orders_today.count(),
        "open_orders": open_orders.count(),
        "orders_to_prepare": open_orders.filter(~Q(fulfillment_mode="inStore")).count(),
        "pending_checks": CheckPayment.objects.filter(business=business, status=CheckPayment.PENDING).count(),
        "receivables_htg": _sum(Customer.objects.filter(business=business), "balance_htg"),
        "low_stock": Product.objects.filter(business=business, is_active=True, track_stock=True,
                                            stock_quantity__lte=F("min_stock")).count(),
        "unread_notifications": Notification.objects.filter(business=business, read_at__isnull=True).count(),
        "cash_session_open": session.exists(),
    }

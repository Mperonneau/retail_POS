"""Orders and quotes. Status and fulfillment values match the register's enums."""

from __future__ import annotations

from decimal import Decimal

from django.db import models

from apps.common.models import TenantModel, UUIDModel

ZERO = Decimal("0")


def money_field(**kwargs):
    return models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, **kwargs)


class Fulfillment:
    IN_STORE = "inStore"
    PICKUP = "pickup"
    DELIVERY = "delivery"
    CHOICES = [(IN_STORE, "En magasin"), (PICKUP, "Retrait"), (DELIVERY, "Livraison")]


class OrderStatus:
    CHECK_PENDING = "checkPending"
    PAID = "paid"
    PARTIALLY_PAID = "partiallyPaid"
    READY = "ready"
    PICKED_UP = "pickedUp"
    DELIVERED = "delivered"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    REFUNDED = "refunded"
    CHOICES = [
        (CHECK_PENDING, "Chèque en attente"),
        (PAID, "Payé"),
        (PARTIALLY_PAID, "Partiellement payée"),
        (READY, "Prêt"),
        (PICKED_UP, "Retiré"),
        (DELIVERED, "Livré"),
        (COMPLETED, "Terminé"),
        (CANCELLED, "Annulée"),
        (REFUNDED, "Remboursée"),
    ]
    TERMINAL = (PICKED_UP, DELIVERED, COMPLETED, CANCELLED, REFUNDED)


class OrderSource:
    POS = "pos"
    PAYMENT_LINK = "paymentLink"
    STOREFRONT = "storefront"
    CHOICES = [(POS, "Caisse"), (PAYMENT_LINK, "Lien de paiement"), (STOREFRONT, "Vitrine")]


class Order(TenantModel):
    number = models.CharField(max_length=30)
    source = models.CharField(max_length=12, choices=OrderSource.CHOICES, default=OrderSource.POS)
    status = models.CharField(max_length=14, choices=OrderStatus.CHOICES, default=OrderStatus.PAID)
    location = models.ForeignKey("accounts.Location", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    device = models.ForeignKey("accounts.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    customer = models.ForeignKey("customers.Customer", null=True, blank=True, on_delete=models.SET_NULL, related_name="orders")
    client_name = models.CharField(max_length=120, blank=True)
    client_phone = models.CharField(max_length=40, blank=True)
    client_email = models.EmailField(blank=True)
    fulfillment_mode = models.CharField(max_length=10, choices=Fulfillment.CHOICES, default=Fulfillment.IN_STORE)
    delivery_location = models.CharField(max_length=300, blank=True)
    delivery_phone = models.CharField(max_length=40, blank=True)
    delivery_fee_htg = money_field()
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    discount_approved_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    tax_percent = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    service_charge_percent = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    subtotal_htg = money_field()
    discount_htg = money_field()
    tax_htg = money_field()
    service_charge_htg = money_field()
    total_htg = money_field()
    amount_paid_htg = money_field()
    balance_due_htg = money_field()
    refunded_htg = money_field()
    usd_rate = models.DecimalField(max_digits=10, decimal_places=4)
    payment_method = models.CharField(max_length=12, blank=True)
    payment_last_four = models.CharField(max_length=4, blank=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)
    from_quote = models.ForeignKey("sales.Quote", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    note = models.CharField(max_length=500, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.CharField(max_length=200, blank=True)
    # When the register rang it up, which can be hours before an offline sync.
    client_created_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["business", "-created_at"], name="order_biz_recent"),
            models.Index(fields=["business", "status"], name="order_biz_status"),
            models.Index(fields=["business", "updated_at"], name="order_biz_sync"),
            models.Index(fields=["business", "number"], name="order_biz_number"),
        ]

    def __str__(self) -> str:
        return self.number


class OrderLine(UUIDModel):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    product_name = models.CharField(max_length=120)
    options_label = models.CharField(max_length=300, blank=True)
    options = models.JSONField(default=list, blank=True)
    measure = models.CharField(max_length=8, blank=True)
    width = models.PositiveIntegerField(default=0)
    quantity = models.PositiveIntegerField()
    unit_price_htg = money_field()
    unit_price_usd = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    unit_cost_htg = money_field()
    line_total_htg = money_field()
    stock_units = models.PositiveIntegerField(default=0)
    refunded_quantity = models.PositiveIntegerField(default=0)
    price_overridden = models.BooleanField(default=False)

    class Meta:
        ordering = ["created_at"]


class OrderStatusEvent(UUIDModel):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="status_events")
    from_status = models.CharField(max_length=14, blank=True)
    to_status = models.CharField(max_length=14)
    actor = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    actor_name = models.CharField(max_length=120, blank=True)
    note = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ["created_at"]


class QuoteStatus:
    DRAFT = "draft"
    CONVERTED = "converted"
    EXPIRED = "expired"
    CANCELLED = "cancelled"
    CHOICES = [(DRAFT, "Brouillon"), (CONVERTED, "Converti"), (EXPIRED, "Expiré"), (CANCELLED, "Annulé")]


class Quote(TenantModel):
    number = models.CharField(max_length=30)
    status = models.CharField(max_length=10, choices=QuoteStatus.CHOICES, default=QuoteStatus.DRAFT)
    source = models.CharField(max_length=12, choices=OrderSource.CHOICES, default=OrderSource.POS)
    location = models.ForeignKey("accounts.Location", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    customer = models.ForeignKey("customers.Customer", null=True, blank=True, on_delete=models.SET_NULL, related_name="quotes")
    client_name = models.CharField(max_length=120, blank=True)
    client_phone = models.CharField(max_length=40, blank=True)
    client_email = models.EmailField(blank=True)
    fulfillment_mode = models.CharField(max_length=10, choices=Fulfillment.CHOICES, default=Fulfillment.IN_STORE)
    delivery_location = models.CharField(max_length=300, blank=True)
    delivery_phone = models.CharField(max_length=40, blank=True)
    delivery_fee_htg = money_field()
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    subtotal_htg = money_field()
    total_htg = money_field()
    note = models.CharField(max_length=500, blank=True)
    valid_until = models.DateField(null=True, blank=True)
    payment_link_sent = models.BooleanField(default=False)
    created_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_by_name = models.CharField(max_length=120, blank=True)
    converted_order = models.ForeignKey(Order, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["business", "status"], name="quote_biz_status"),
            models.Index(fields=["business", "updated_at"], name="quote_biz_sync"),
        ]


class QuoteLine(UUIDModel):
    quote = models.ForeignKey(Quote, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    product_name = models.CharField(max_length=120)
    options_label = models.CharField(max_length=300, blank=True)
    choices = models.JSONField(default=list, blank=True)
    measure = models.CharField(max_length=8, blank=True)
    width = models.PositiveIntegerField(default=0)
    quantity = models.PositiveIntegerField()
    unit_price_htg = money_field()
    line_total_htg = money_field()
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "created_at"]


class Refund(TenantModel):
    METHODS = [
        ("cash", "Espèces"),
        ("cashUsd", "Espèces (USD)"),
        ("card", "Carte"),
        ("moncash", "MonCash"),
        ("storeCredit", "Avoir client"),
        ("credit", "Réduction du solde client"),
    ]

    order = models.ForeignKey(Order, on_delete=models.PROTECT, related_name="refunds")
    number = models.CharField(max_length=30)
    amount_htg = money_field()
    method = models.CharField(max_length=12, choices=METHODS)
    reason = models.CharField(max_length=300)
    restock = models.BooleanField(default=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-created_at"]


class RefundLine(UUIDModel):
    refund = models.ForeignKey(Refund, on_delete=models.CASCADE, related_name="lines")
    order_line = models.ForeignKey(OrderLine, on_delete=models.PROTECT, related_name="+")
    quantity = models.PositiveIntegerField()
    amount_htg = money_field()

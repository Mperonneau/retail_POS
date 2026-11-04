from decimal import Decimal

from django.db import models

from apps.common.models import TenantModel

ZERO = Decimal("0")


class Payment(TenantModel):
    """One tender applied to an order. A sale can have several."""

    CASH = "cash"
    CASH_USD = "cashUsd"
    CARD = "card"
    MONCASH = "moncash"
    NATCASH = "natcash"
    CHECK = "check"
    CREDIT = "credit"
    STORE_CREDIT = "storeCredit"
    PAYMENT_LINK = "paymentLink"
    METHODS = [
        (CASH, "Espèces"),
        (CASH_USD, "Espèces (USD)"),
        (CARD, "Carte"),
        (MONCASH, "MonCash"),
        (NATCASH, "NatCash"),
        (CHECK, "Chèque"),
        (CREDIT, "Crédit client"),
        (STORE_CREDIT, "Avoir"),
        (PAYMENT_LINK, "Lien de paiement"),
    ]
    ELECTRONIC = (CARD, MONCASH, NATCASH, PAYMENT_LINK)

    CONFIRMED = "confirmed"
    PENDING = "pending"
    FAILED = "failed"
    REFUNDED = "refunded"
    STATUSES = [(CONFIRMED, "Confirmé"), (PENDING, "En attente"), (FAILED, "Refusé"), (REFUNDED, "Remboursé")]

    order = models.ForeignKey("sales.Order", on_delete=models.CASCADE, related_name="payments")
    method = models.CharField(max_length=12, choices=METHODS)
    status = models.CharField(max_length=10, choices=STATUSES, default=CONFIRMED)
    # Value applied to the order, in HTG at the order's rate.
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    # Bills or card charge in dollars, when the tender was in USD.
    amount_usd = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    tendered_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    change_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    reference = models.CharField(max_length=120, blank=True)
    last_four = models.CharField(max_length=4, blank=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)
    paylink = models.ForeignKey("payments.PayLink", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["created_at"]
        indexes = [models.Index(fields=["business", "method", "created_at"], name="payment_biz_method")]


class CheckPayment(TenantModel):
    PENDING = "pending"
    CLEARED = "cleared"
    REFUSED = "refused"
    STATUSES = [(PENDING, "En attente de compensation"), (CLEARED, "Compensé"), (REFUSED, "Refusé")]

    payment = models.OneToOneField(Payment, on_delete=models.CASCADE, related_name="check_details")
    number = models.CharField(max_length=40)
    bank = models.CharField(max_length=80)
    payer_name = models.CharField(max_length=120)
    check_date = models.DateField()
    # Private storage path. Check scans are never served publicly.
    image = models.CharField(max_length=200, blank=True)
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    status = models.CharField(max_length=8, choices=STATUSES, default=PENDING)
    cleared_at = models.DateTimeField(null=True, blank=True)
    cleared_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    cleared_by_name = models.CharField(max_length=120, blank=True)
    refused_at = models.DateTimeField(null=True, blank=True)
    refused_reason = models.CharField(max_length=200, blank=True)
    credit_customer = models.ForeignKey("customers.Customer", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    credit_posted = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "status"], name="check_biz_status")]

    @property
    def clearance_label(self) -> str:
        if self.status == self.REFUSED:
            return "Chèque refusé"
        if self.status != self.CLEARED:
            return "En attente de compensation"
        return f"Chèque compensé par : {self.cleared_by_name}" if self.cleared_by_name else "Chèque compensé"


class PayLink(TenantModel):
    ACTIVE = "active"
    PAID = "paidUnused"
    INACTIVE = "inactive"
    STATUSES = [(ACTIVE, "Actif"), (PAID, "Payé"), (INACTIVE, "Inactif")]
    CHANNELS = [("whatsApp", "WhatsApp"), ("email", "E-mail"), ("sms", "SMS")]
    SOURCES = [("standalone", "Lien seul"), ("orderBill", "Facture de commande")]

    reference = models.CharField(max_length=30)
    customer = models.ForeignKey("customers.Customer", null=True, blank=True, on_delete=models.SET_NULL, related_name="paylinks")
    customer_name = models.CharField(max_length=120, blank=True)
    customer_phone = models.CharField(max_length=40, blank=True)
    payer_email = models.EmailField(blank=True)
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    usd_rate = models.DecimalField(max_digits=10, decimal_places=4)
    order_usd_cents = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=12, choices=STATUSES, default=ACTIVE)
    channel = models.CharField(max_length=10, choices=CHANNELS, default="whatsApp")
    source = models.CharField(max_length=12, choices=SOURCES, default="standalone")
    sent_to = models.CharField(max_length=120, blank=True)
    order = models.ForeignKey("sales.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="paylinks")
    note = models.CharField(max_length=300, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    canceled_at = models.DateTimeField(null=True, blank=True)
    canceled_by = models.CharField(max_length=120, blank=True)
    created_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_by_name = models.CharField(max_length=120, blank=True)
    payment_url = models.URLField(max_length=600, blank=True)
    stripe_session_id = models.CharField(max_length=120, blank=True, db_index=True)
    payer_total_usd_cents = models.PositiveIntegerField(null=True, blank=True)
    platform_fee_usd_cents = models.PositiveIntegerField(null=True, blank=True)
    stripe_fee_usd_cents = models.PositiveIntegerField(null=True, blank=True)
    payment_transaction_id = models.CharField(max_length=120, blank=True)
    payment_last4 = models.CharField(max_length=4, blank=True)
    payment_method = models.CharField(max_length=20, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["business", "reference"], name="uniq_paylink_reference")]
        indexes = [models.Index(fields=["business", "status"], name="paylink_biz_status")]


class WebhookEvent(models.Model):
    """Provider events already handled, so a redelivery is ignored."""

    provider = models.CharField(max_length=20)
    event_id = models.CharField(max_length=120)
    kind = models.CharField(max_length=80)
    processed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["provider", "event_id"], name="uniq_webhook_event")]

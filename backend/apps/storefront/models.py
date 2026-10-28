from __future__ import annotations

from decimal import Decimal

from django.db import models
from django.utils import timezone

from apps.common.models import TimeStampedModel, UUIDModel

ZERO = Decimal("0")


class StorefrontShop(UUIDModel):
    """The public vitrine of one business. Products come from its catalog."""

    business = models.OneToOneField("accounts.Business", on_delete=models.CASCADE, related_name="storefront")
    # SHA-256 of the register's X-Shop-Key. Lets the current app publish.
    key_hash = models.CharField(max_length=64, unique=True, null=True, blank=True)
    slug = models.CharField(max_length=40, unique=True, null=True, blank=True)
    name = models.CharField(max_length=80)
    phone = models.CharField(max_length=40, blank=True)
    address = models.CharField(max_length=160, blank=True)
    city = models.CharField(max_length=60, blank=True)
    department = models.CharField(max_length=40, blank=True)
    categories = models.JSONField(default=list, blank=True)
    description = models.CharField(max_length=300, blank=True)
    pickup_note = models.CharField(max_length=300, blank=True)
    cover = models.CharField(max_length=80, blank=True)
    enabled = models.BooleanField(default=False)
    paused = models.BooleanField(default=False)
    accept_when_closed = models.BooleanField(default=True)
    open_hour = models.PositiveSmallIntegerField(default=8)
    close_hour = models.PositiveSmallIntegerField(default=18)
    closed_weekdays = models.JSONField(default=list, blank=True)
    # 0 means the business rate.
    usd_rate = models.DecimalField(max_digits=10, decimal_places=4, default=ZERO)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["enabled", "department"], name="shop_directory")]

    def __str__(self) -> str:
        return self.slug or self.name

    def effective_rate(self) -> Decimal:
        if self.usd_rate and self.usd_rate > 0:
            return self.usd_rate
        return self.business.settings.effective_usd_rate()


class ShopperAccount(UUIDModel):
    """A vitrine customer, identified by a verified phone number."""

    phone_digits = models.CharField(max_length=20, unique=True)
    phone = models.CharField(max_length=40)
    country = models.CharField(max_length=2, blank=True)
    name = models.CharField(max_length=80)
    email = models.EmailField(blank=True)
    # Legacy personal code sign-in (hashed with the server pepper).
    pin_hash = models.CharField(max_length=128, blank=True)
    firebase_uid = models.CharField(max_length=128, null=True, blank=True, unique=True)

    def __str__(self) -> str:
        return self.phone


class ShopperSession(UUIDModel):
    account = models.ForeignKey(ShopperAccount, on_delete=models.CASCADE, related_name="sessions")
    token_hash = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)

    def is_valid(self) -> bool:
        return self.revoked_at is None and self.expires_at > timezone.now()


class PhoneVerification(UUIDModel):
    phone_digits = models.CharField(max_length=20, db_index=True)
    phone = models.CharField(max_length=20)
    country = models.CharField(max_length=2)
    # Empty when the provider (Twilio Verify, Firebase) holds the code.
    code_hash = models.CharField(max_length=64, blank=True)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    verified_at = models.DateTimeField(null=True, blank=True)


class ShopperSignup(UUIDModel):
    """Proof that a new number was verified, spent when the account is named."""

    token_hash = models.CharField(max_length=64, unique=True)
    phone_digits = models.CharField(max_length=20)
    phone = models.CharField(max_length=20)
    country = models.CharField(max_length=2)
    expires_at = models.DateTimeField()


class StorefrontRequest(TimeStampedModel):
    """A devis or commande behind an unguessable link that anyone can pay."""

    DEVIS = "devis"
    COMMANDE = "commande"
    KINDS = [(DEVIS, "Devis"), (COMMANDE, "Commande")]

    OPEN = "open"
    PAID = "paid"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    STATUSES = [(OPEN, "Ouverte"), (PAID, "Payée"), (CANCELLED, "Annulée"), (EXPIRED, "Expirée")]

    id = models.CharField(primary_key=True, max_length=64)
    shop = models.ForeignKey(StorefrontShop, on_delete=models.CASCADE, related_name="requests")
    business = models.ForeignKey("accounts.Business", on_delete=models.CASCADE, related_name="+")
    number = models.CharField(max_length=30)
    kind = models.CharField(max_length=8, choices=KINDS)
    status = models.CharField(max_length=9, choices=STATUSES, default=OPEN)
    source = models.CharField(max_length=10, default="storefront")
    customer_name = models.CharField(max_length=80)
    customer_phone = models.CharField(max_length=40)
    customer_email = models.EmailField(blank=True)
    account = models.ForeignKey(ShopperAccount, null=True, blank=True, on_delete=models.SET_NULL, related_name="requests")
    note = models.CharField(max_length=500, blank=True)
    fulfillment_mode = models.CharField(max_length=10, default="inStore")
    delivery_location = models.CharField(max_length=300, blank=True)
    # Priced snapshot: product_id, name, options, options_label, quantity,
    # unit_htg, total_htg, stock_units, measure, width, choices.
    lines = models.JSONField(default=list)
    discount_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    total_htg = models.DecimalField(max_digits=14, decimal_places=2)
    usd_rate = models.DecimalField(max_digits=10, decimal_places=4)
    external_ref = models.CharField(max_length=40, blank=True)
    stock_reserved = models.BooleanField(default=False)
    reserved_until = models.DateTimeField(null=True, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    payment_method = models.CharField(max_length=10, blank=True)
    payment_reference = models.CharField(max_length=120, blank=True)
    payment_amount = models.PositiveIntegerField(default=0)
    payment_currency = models.CharField(max_length=3, blank=True)
    card_intent_id = models.CharField(max_length=120, blank=True)
    moncash_order_id = models.CharField(max_length=60, blank=True)
    order = models.ForeignKey("sales.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    quote = models.ForeignKey("sales.Quote", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    imported_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["shop", "-created_at"], name="sfreq_shop_recent"),
            models.Index(fields=["status", "reserved_until"], name="sfreq_reservations"),
            models.Index(fields=["shop", "external_ref"], name="sfreq_external"),
        ]

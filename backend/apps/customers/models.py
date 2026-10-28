from __future__ import annotations

import re
from decimal import Decimal

from django.db import models

from apps.common.models import TenantModel

ZERO = Decimal("0")


def phone_digits(value: str) -> str:
    return re.sub(r"\D", "", value or "")


class Customer(TenantModel):
    name = models.CharField(max_length=120)
    first_name = models.CharField(max_length=60, blank=True)
    last_name = models.CharField(max_length=60, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    phone_digits = models.CharField(max_length=20, blank=True, db_index=True, editable=False)
    secondary_phone = models.CharField(max_length=40, blank=True)
    email = models.EmailField(blank=True)
    address = models.CharField(max_length=200, blank=True)
    notes = models.TextField(blank=True, max_length=1000)
    date_of_birth = models.DateField(null=True, blank=True)
    government_id = models.CharField(max_length=40, blank=True)
    credit_limit_htg = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    credit_limit_usd = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    is_credit_blocked = models.BooleanField(default=False)
    blocked_reason = models.CharField(max_length=200, blank=True)
    blocked_by = models.CharField(max_length=120, blank=True)
    blocked_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    # Cached from the ledgers inside the same transaction that posts an entry.
    balance_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    store_credit_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    total_spent_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    total_purchases = models.PositiveIntegerField(default=0)
    last_purchase_at = models.DateTimeField(null=True, blank=True)
    external_id = models.CharField(max_length=40, null=True, blank=True)

    class Meta:
        ordering = ["name"]
        indexes = [
            models.Index(fields=["business", "name"], name="customer_biz_name"),
            models.Index(fields=["business", "updated_at"], name="customer_biz_sync"),
            models.Index(fields=["business", "-balance_htg"], name="customer_biz_balance"),
        ]

    def __str__(self) -> str:
        return self.name

    def save(self, *args, **kwargs):
        self.phone_digits = phone_digits(self.phone)[:20]
        if not self.name.strip():
            self.name = f"{self.first_name} {self.last_name}".strip()
        update_fields = kwargs.get("update_fields")
        if update_fields is not None and "phone" in update_fields:
            kwargs["update_fields"] = list({*update_fields, "phone_digits"})
        super().save(*args, **kwargs)

    @property
    def has_store_credit_identity(self) -> bool:
        if not self.first_name.strip() or not self.last_name.strip():
            return False
        return bool(self.government_id.strip()) or self.date_of_birth is not None

    @property
    def is_over_limit(self) -> bool:
        return self.credit_limit_htg is not None and self.balance_htg >= self.credit_limit_htg


class CustomerTransaction(TenantModel):
    CHARGE = "charge"
    PAYMENT = "payment"
    ADJUSTMENT = "adjustment"
    KINDS = [(CHARGE, "Vente à crédit"), (PAYMENT, "Paiement"), (ADJUSTMENT, "Ajustement")]

    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="transactions")
    kind = models.CharField(max_length=10, choices=KINDS)
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    amount_usd = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    paid_amount_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    balance_after_htg = models.DecimalField(max_digits=14, decimal_places=2)
    order = models.ForeignKey("sales.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    description = models.CharField(max_length=200)
    payment_method = models.CharField(max_length=20, blank=True)
    receipt_number = models.CharField(max_length=30, blank=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)
    receipt_sent = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "customer", "-created_at"], name="custtx_biz_customer")]

    @property
    def credited_htg(self) -> Decimal:
        return self.amount_htg - self.paid_amount_htg


class StoreCreditEntry(TenantModel):
    ISSUED = "issued"
    REDEEMED = "redeemed"
    KINDS = [(ISSUED, "Avoir émis"), (REDEEMED, "Avoir utilisé")]

    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="store_credit_entries")
    kind = models.CharField(max_length=10, choices=KINDS)
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    balance_after_htg = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    description = models.CharField(max_length=200)
    order = models.ForeignKey("sales.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    paylink = models.ForeignKey("payments.PayLink", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-created_at"]


class CustomerNote(TenantModel):
    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="note_entries")
    text = models.TextField(max_length=1000)
    created_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_by_name = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-created_at"]


class PaymentSchedule(TenantModel):
    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="schedules")
    scheduled_date = models.DateField()
    amount_htg = models.DecimalField(max_digits=14, decimal_places=2)
    is_paid = models.BooleanField(default=False)
    paid_at = models.DateTimeField(null=True, blank=True)
    note = models.CharField(max_length=200, blank=True)

    class Meta:
        ordering = ["scheduled_date"]

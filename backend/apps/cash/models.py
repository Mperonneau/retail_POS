from decimal import Decimal

from django.db import models
from django.db.models import Q
from django.utils import timezone

from apps.common.models import TenantModel

ZERO = Decimal("0")


def money_field(**kwargs):
    return models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, **kwargs)


class CashSession(TenantModel):
    OPEN = "open"
    CLOSED = "closed"

    location = models.ForeignKey("accounts.Location", on_delete=models.PROTECT, related_name="cash_sessions")
    status = models.CharField(max_length=6, choices=[(OPEN, "Ouverte"), (CLOSED, "Fermée")], default=OPEN)
    opened_by = models.ForeignKey("accounts.StaffMember", null=True, on_delete=models.SET_NULL, related_name="+")
    opened_by_name = models.CharField(max_length=120)
    opened_at = models.DateTimeField(default=timezone.now)
    opening_htg = money_field()
    opening_usd = money_field()
    closed_at = models.DateTimeField(null=True, blank=True)
    closed_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    closed_by_name = models.CharField(max_length=120, blank=True)
    closing_note = models.TextField(blank=True, max_length=1000)
    # Filled at close: drawer cash only (card and MonCash are not in the till).
    total_in_htg = money_field()
    total_in_usd = money_field()
    total_out_htg = money_field()
    total_out_usd = money_field()
    expected_htg = money_field()
    expected_usd = money_field()
    counted_htg = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    counted_usd = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    over_short_htg = money_field()
    over_short_usd = money_field()

    class Meta:
        ordering = ["-opened_at"]
        constraints = [
            models.UniqueConstraint(fields=["location"], condition=Q(status="open"), name="one_open_session_per_location"),
        ]


class CashMovement(TenantModel):
    CASH_IN = "cashIn"
    CASH_OUT = "cashOut"
    ADJUSTMENT = "adjustment"
    TYPES = [(CASH_IN, "Entrée"), (CASH_OUT, "Sortie"), (ADJUSTMENT, "Ajustement")]

    CASH_HTG = "cashHtg"
    CASH_USD = "cashUsd"
    MONCASH = "moncash"
    CARD = "card"
    CHECK = "check"
    TENDERS = [
        (CASH_HTG, "Espèces (HTG)"),
        (CASH_USD, "Espèces (USD)"),
        (MONCASH, "MonCash"),
        (CARD, "Carte"),
        (CHECK, "Chèque"),
    ]
    DRAWER_TENDERS = (CASH_HTG, CASH_USD)

    session = models.ForeignKey(CashSession, on_delete=models.PROTECT, related_name="movements")
    type = models.CharField(max_length=10, choices=TYPES)
    tender = models.CharField(max_length=8, choices=TENDERS, default=CASH_HTG)
    amount_htg = money_field()
    amount_usd = money_field()
    tips_htg = money_field()
    tips_usd = money_field()
    description = models.CharField(max_length=200)
    order = models.ForeignKey("sales.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="cash_movements")
    reference = models.CharField(max_length=40, blank=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    recorded_by_name = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["session", "tender"], name="cashmov_session_tender")]


class ShiftHandoff(TenantModel):
    session = models.ForeignKey(CashSession, on_delete=models.CASCADE, related_name="handoffs")
    closed_by = models.ForeignKey("accounts.StaffMember", null=True, on_delete=models.SET_NULL, related_name="+")
    closed_by_name = models.CharField(max_length=120)
    received_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    received_by_name = models.CharField(max_length=120)
    opening_htg = money_field()
    opening_usd = money_field()
    inflow_htg = money_field()
    inflow_usd = money_field()
    outflow_htg = money_field()
    outflow_usd = money_field()
    expected_htg = money_field()
    expected_usd = money_field()
    counted_htg = money_field()
    counted_usd = money_field()
    note = models.CharField(max_length=500, blank=True)

    class Meta:
        ordering = ["-created_at"]

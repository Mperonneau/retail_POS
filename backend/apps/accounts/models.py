from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q
from django.utils import timezone

from apps.common.models import TenantModel, UUIDModel

from . import roles


class Business(UUIDModel):
    name = models.CharField(max_length=120)
    legal_name = models.CharField(max_length=160, blank=True)
    owner_name = models.CharField(max_length=120, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    email = models.EmailField(blank=True)
    address = models.CharField(max_length=200, blank=True)
    city = models.CharField(max_length=60, blank=True)
    department = models.CharField(max_length=40, blank=True)
    country = models.CharField(max_length=2, default="HT")
    logo = models.CharField(max_length=80, blank=True)
    is_active = models.BooleanField(default=True)
    plan = models.CharField(max_length=40, default="pro")
    plan_renews_at = models.DateField(null=True, blank=True)

    class Meta:
        verbose_name_plural = "businesses"

    def __str__(self) -> str:
        return self.name


class BusinessSettings(UUIDModel):
    LOCAL_ONLY = "localOnly"
    USD_ONLY = "usdOnly"
    BOTH = "both"
    CURRENCY_MODES = [(LOCAL_ONLY, "Gourdes"), (USD_ONLY, "Dollars"), (BOTH, "Gourdes et dollars")]

    business = models.OneToOneField(Business, on_delete=models.CASCADE, related_name="settings")
    currency_mode = models.CharField(max_length=10, choices=CURRENCY_MODES, default=BOTH)
    local_currency = models.CharField(max_length=3, default="HTG")
    usd_rate = models.DecimalField(max_digits=10, decimal_places=4, default=Decimal("135"))
    tax_enabled = models.BooleanField(default=False)
    tax_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("10"))
    service_fee_enabled = models.BooleanField(default=False)
    service_fee_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("10"))
    discounts_allowed = models.BooleanField(default=True)
    discount_approval_code_hash = models.CharField(max_length=128, blank=True)
    receipt_name = models.CharField(max_length=120, blank=True)
    receipt_header = models.TextField(blank=True, max_length=500)
    receipt_footer = models.TextField(blank=True, max_length=500)
    pickup_enabled = models.BooleanField(default=True)
    delivery_enabled = models.BooleanField(default=True)
    default_delivery_fee_htg = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0"))
    language = models.CharField(max_length=2, choices=[("kr", "Kreyòl"), ("fr", "Français"), ("en", "English")], default="fr")
    theme = models.CharField(max_length=6, choices=[("auto", "Auto"), ("light", "Clair"), ("dark", "Sombre")], default="auto")
    offline_window_days = models.PositiveSmallIntegerField(default=settings.DEVICE_OFFLINE_WINDOW_DAYS)
    require_open_cash_session = models.BooleanField(default=False)
    # {role: {permission: bool}} on top of roles.ROLE_DEFAULTS.
    role_permissions = models.JSONField(default=dict, blank=True)

    def effective_usd_rate(self) -> Decimal:
        return self.usd_rate if self.usd_rate and self.usd_rate > 0 else Decimal(str(settings.DEFAULT_DAY_USD_RATE))


class ExchangeRate(TenantModel):
    """History of HTG per USD so every sale can be explained later."""

    rate = models.DecimalField(max_digits=10, decimal_places=4)
    effective_at = models.DateTimeField(default=timezone.now)
    set_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-effective_at"]


class Location(TenantModel):
    name = models.CharField(max_length=120)
    address = models.CharField(max_length=200, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    is_default = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-is_default", "name"]

    def __str__(self) -> str:
        return self.name


class StaffMember(TenantModel):
    """Everyone who uses the register, including the owner.

    This is also the authenticated principal on API requests.
    """

    full_name = models.CharField(max_length=120)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=40, blank=True)
    role = models.CharField(max_length=10, choices=roles.ROLE_CHOICES, default=roles.SELLER)
    pin_lookup = models.CharField(max_length=64, null=True, blank=True, editable=False)
    firebase_uid = models.CharField(max_length=128, null=True, blank=True, db_index=True)
    is_active = models.BooleanField(default=True)
    permission_overrides = models.JSONField(default=dict, blank=True)
    default_location = models.ForeignKey(Location, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    last_login_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["full_name"]
        constraints = [
            models.UniqueConstraint(
                fields=["business", "pin_lookup"], condition=Q(pin_lookup__isnull=False), name="uniq_staff_pin"
            ),
            models.UniqueConstraint(
                fields=["business", "firebase_uid"], condition=Q(firebase_uid__isnull=False), name="uniq_staff_firebase"
            ),
        ]

    def __str__(self) -> str:
        return self.full_name

    is_authenticated = True
    is_anonymous = False

    @property
    def permissions(self) -> dict[str, bool]:
        cached = getattr(self, "_permissions_cache", None)
        if cached is None:
            business_settings = getattr(self.business, "settings", None)
            cached = roles.effective_permissions(
                self.role,
                business_settings.role_permissions if business_settings else {},
                self.permission_overrides,
            )
            self._permissions_cache = cached
        return cached

    def has_perm_code(self, code: str) -> bool:
        return self.is_active and bool(self.permissions.get(code))

    @property
    def has_pin(self) -> bool:
        return bool(self.pin_lookup)


class DeviceInvite(TenantModel):
    code_hash = models.CharField(max_length=64, unique=True)
    location = models.ForeignKey(Location, on_delete=models.CASCADE, related_name="+")
    device_name = models.CharField(max_length=80, blank=True)
    created_by = models.ForeignKey(StaffMember, null=True, on_delete=models.SET_NULL, related_name="+")
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    device = models.ForeignKey("accounts.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    def is_live(self) -> bool:
        return self.used_at is None and self.expires_at > timezone.now()


class Device(TenantModel):
    name = models.CharField(max_length=80)
    location = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="devices")
    token_hash = models.CharField(max_length=64, unique=True)
    platform = models.CharField(max_length=40, blank=True)
    app_version = models.CharField(max_length=40, blank=True)
    paired_at = models.DateTimeField(default=timezone.now)
    last_verified_at = models.DateTimeField(default=timezone.now)
    revoked_at = models.DateTimeField(null=True, blank=True)
    failed_pin_attempts = models.PositiveSmallIntegerField(default=0)
    pin_locked_until = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-paired_at"]

    @property
    def is_revoked(self) -> bool:
        return self.revoked_at is not None


class StaffSession(UUIDModel):
    """Bearer session for API calls: PIN on a paired register, or an owner login."""

    PIN = "pin"
    OWNER = "owner"

    business = models.ForeignKey(Business, on_delete=models.CASCADE, related_name="+")
    staff = models.ForeignKey(StaffMember, on_delete=models.CASCADE, related_name="sessions")
    device = models.ForeignKey(Device, null=True, blank=True, on_delete=models.CASCADE, related_name="sessions")
    kind = models.CharField(max_length=8, choices=[(PIN, "PIN"), (OWNER, "Connexion")], default=PIN)
    token_hash = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()
    last_seen_at = models.DateTimeField(default=timezone.now)
    revoked_at = models.DateTimeField(null=True, blank=True)

    def is_valid(self) -> bool:
        return self.revoked_at is None and self.expires_at > timezone.now()

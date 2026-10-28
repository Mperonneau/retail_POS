from __future__ import annotations

from rest_framework import serializers

from apps.common.serializers import tenant_fk

from . import roles
from .models import Business, BusinessSettings, Device, DeviceInvite, ExchangeRate, Location, StaffMember


class BusinessSerializer(serializers.ModelSerializer):
    class Meta:
        model = Business
        fields = [
            "id", "name", "legal_name", "owner_name", "phone", "email", "address", "city", "department",
            "country", "plan", "plan_renews_at", "created_at",
        ]
        read_only_fields = ["id", "plan", "plan_renews_at", "created_at"]


class BusinessSettingsSerializer(serializers.ModelSerializer):
    discount_approval_code = serializers.CharField(write_only=True, required=False, allow_blank=True, max_length=40)
    has_discount_approval_code = serializers.SerializerMethodField()

    class Meta:
        model = BusinessSettings
        fields = [
            "currency_mode", "local_currency", "usd_rate", "tax_enabled", "tax_percent", "service_fee_enabled",
            "service_fee_percent", "discounts_allowed", "discount_approval_code", "has_discount_approval_code",
            "receipt_name", "receipt_header", "receipt_footer", "pickup_enabled", "delivery_enabled",
            "default_delivery_fee_htg", "language", "theme", "offline_window_days", "require_open_cash_session",
            "role_permissions", "updated_at",
        ]
        read_only_fields = ["usd_rate", "updated_at"]

    def get_has_discount_approval_code(self, obj) -> bool:
        return bool(obj.discount_approval_code_hash)

    def validate_tax_percent(self, value):
        if value < 0 or value > 100:
            raise serializers.ValidationError("Entre 0 et 100 %.")
        return value

    validate_service_fee_percent = validate_tax_percent

    def validate_offline_window_days(self, value):
        if not 1 <= value <= 30:
            raise serializers.ValidationError("Entre 1 et 30 jours.")
        return value

    def validate_role_permissions(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("Format invalide.")
        cleaned = {}
        for role, perms in value.items():
            if role not in roles.ROLE_DEFAULTS or role == roles.OWNER:
                continue
            cleaned[role] = roles.clean_permission_map(perms)
        return cleaned

    def update(self, instance, validated_data):
        code = validated_data.pop("discount_approval_code", None)
        instance = super().update(instance, validated_data)
        if code is not None:
            from .services import set_discount_code

            set_discount_code(instance, code)
        return instance


class ExchangeRateSerializer(serializers.ModelSerializer):
    set_by_name = serializers.CharField(source="set_by.full_name", read_only=True, default="")

    class Meta:
        model = ExchangeRate
        fields = ["id", "rate", "effective_at", "set_by_name"]


class LocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Location
        fields = ["id", "name", "address", "phone", "is_default", "is_active", "updated_at"]
        read_only_fields = ["id", "updated_at"]


class StaffMemberSerializer(serializers.ModelSerializer):
    has_pin = serializers.BooleanField(read_only=True)
    permissions = serializers.DictField(child=serializers.BooleanField(), read_only=True)
    default_location = tenant_fk(Location.objects.all())

    class Meta:
        model = StaffMember
        fields = [
            "id", "full_name", "email", "phone", "role", "is_active", "has_pin", "permission_overrides",
            "permissions", "default_location", "last_login_at", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "last_login_at", "created_at", "updated_at"]

    def validate_full_name(self, value):
        value = value.strip()
        if len(value) < 2:
            raise serializers.ValidationError("Indiquez le nom complet.")
        return value

    def validate_permission_overrides(self, value):
        return roles.clean_permission_map(value)

    def validate(self, attrs):
        actor = self.context["request"].user
        target_role = attrs.get("role", getattr(self.instance, "role", None))
        current_role = getattr(self.instance, "role", None)
        privileged = {roles.OWNER, roles.ADMIN}
        if (target_role in privileged or current_role in privileged) and actor.role != roles.OWNER:
            raise serializers.ValidationError("Seul le propriétaire peut gérer les administrateurs.")
        if self.instance is not None and self.instance.role == roles.OWNER:
            if attrs.get("role", roles.OWNER) != roles.OWNER or attrs.get("is_active") is False:
                raise serializers.ValidationError("Le compte du propriétaire ne peut pas être rétrogradé ni désactivé.")
        return attrs


class StaffRosterSerializer(serializers.ModelSerializer):
    """What a paired register may cache: no contact details, no secrets."""

    class Meta:
        model = StaffMember
        fields = ["id", "full_name", "role", "is_active"]


class DeviceSerializer(serializers.ModelSerializer):
    location_name = serializers.CharField(source="location.name", read_only=True)

    class Meta:
        model = Device
        fields = [
            "id", "name", "location", "location_name", "platform", "app_version", "paired_at",
            "last_verified_at", "revoked_at",
        ]
        read_only_fields = fields


class DeviceInviteSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceInvite
        fields = ["id", "location", "device_name", "expires_at", "used_at", "created_at"]
        read_only_fields = fields


def session_payload(staff: StaffMember, token: str, session) -> dict:
    business = staff.business
    business_settings = business.settings
    return {
        "token": token,
        "token_type": "Staff",
        "expires_at": session.expires_at,
        "staff": {
            "id": str(staff.pk),
            "full_name": staff.full_name,
            "role": staff.role,
            "permissions": staff.permissions,
            "idle_lock_minutes": roles.IDLE_LOCK_MINUTES.get(staff.role, 15),
        },
        "business": BusinessSerializer(business).data,
        "settings": BusinessSettingsSerializer(business_settings).data,
    }

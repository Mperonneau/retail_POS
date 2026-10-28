from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.common.audit import audit
from apps.common.exceptions import ApiError

from . import roles
from .models import Business, BusinessSettings, Device, DeviceInvite, ExchangeRate, Location, StaffMember, StaffSession
from .security import generate_device_code, hash_token, new_token, normalize_device_code, pin_lookup, validate_pin


@transaction.atomic
def register_business(*, firebase_uid: str, business_name: str, owner_name: str, email: str = "", phone: str = "",
                      location_name: str = "", city: str = "", department: str = "") -> tuple[Business, StaffMember]:
    name = (business_name or "").strip()[:120]
    owner = (owner_name or "").strip()[:120]
    if len(name) < 2:
        raise ApiError("Indiquez le nom de la boutique.")
    if len(owner) < 2:
        raise ApiError("Indiquez le nom du propriétaire.")
    business = Business.objects.create(
        name=name, owner_name=owner, email=email[:254], phone=phone[:40], city=city[:60], department=department[:40]
    )
    BusinessSettings.objects.create(business=business, receipt_name=name)
    location = Location.objects.create(business=business, name=(location_name or name)[:120], is_default=True)
    staff = StaffMember.objects.create(
        business=business,
        full_name=owner,
        email=email[:254],
        phone=phone[:40],
        role=roles.OWNER,
        firebase_uid=firebase_uid,
        default_location=location,
    )
    audit(business, "business.registered", actor=staff, target=business)
    return business, staff


def issue_session(staff: StaffMember, *, kind: str, device: Device | None = None) -> tuple[str, StaffSession]:
    raw = new_token()
    now = timezone.now()
    lifetime = (
        timedelta(hours=settings.STAFF_SESSION_HOURS)
        if kind == StaffSession.PIN
        else timedelta(days=settings.OWNER_SESSION_DAYS)
    )
    session = StaffSession.objects.create(
        business=staff.business,
        staff=staff,
        device=device,
        kind=kind,
        token_hash=hash_token(raw),
        expires_at=now + lifetime,
    )
    StaffMember.objects.filter(pk=staff.pk).update(last_login_at=now)
    return raw, session


def create_device_invite(staff: StaffMember, *, location: Location | None, device_name: str = "") -> tuple[str, DeviceInvite]:
    business = staff.business
    location = location or Location.objects.filter(business=business, is_default=True).first()
    if location is None:
        raise ApiError("Ajoutez d'abord un point de vente.")
    for _ in range(5):
        code = generate_device_code()
        try:
            with transaction.atomic():
                invite = DeviceInvite.objects.create(
                    business=business,
                    code_hash=hash_token(code),
                    location=location,
                    device_name=device_name[:80],
                    created_by=staff,
                    expires_at=timezone.now() + timedelta(hours=settings.DEVICE_INVITE_HOURS),
                )
            break
        except IntegrityError:
            continue
    else:
        raise ApiError("Réessayez dans un instant.", 503)
    audit(business, "device.invite_created", actor=staff, target=invite, location=str(location.pk))
    return code, invite


@transaction.atomic
def pair_device(*, code: str, device_name: str, platform: str = "", app_version: str = "") -> tuple[str, Device]:
    normalized = normalize_device_code(code)
    if len(normalized.replace("-", "")) != 8:
        raise ApiError("Le code doit avoir 8 caractères.")
    invite = (
        DeviceInvite.objects.select_for_update()
        .select_related("business", "location")
        .filter(code_hash=hash_token(normalized))
        .first()
    )
    if invite is None or not invite.is_live() or not invite.business.is_active:
        raise ApiError("Ce code n'est pas valide ou a expiré. Demandez-en un nouveau.", 400)
    raw = new_token()
    device = Device.objects.create(
        business=invite.business,
        location=invite.location,
        name=(device_name or invite.device_name or "Caisse")[:80],
        token_hash=hash_token(raw),
        platform=platform[:40],
        app_version=app_version[:40],
    )
    invite.used_at = timezone.now()
    invite.device = device
    invite.save(update_fields=["used_at", "device", "updated_at"])
    audit(invite.business, "device.paired", target=device, device=device)
    return raw, device


def verify_device(device: Device, *, app_version: str = "") -> Device:
    device.last_verified_at = timezone.now()
    fields = ["last_verified_at", "updated_at"]
    if app_version:
        device.app_version = app_version[:40]
        fields.append("app_version")
    device.save(update_fields=fields)
    return device


def unlock_with_pin(device: Device, pin: str) -> tuple[str, StaffMember, StaffSession]:
    """PIN sign-in on a paired register, with a lock after repeated misses."""
    value = validate_pin(pin)
    now = timezone.now()
    with transaction.atomic():
        locked = Device.objects.select_for_update().get(pk=device.pk)
        if locked.pin_locked_until and locked.pin_locked_until > now:
            raise ApiError("Trop d'essais. Réessayez dans quelques minutes.", 429)
        staff = (
            StaffMember.objects.select_related("business__settings")
            .filter(business=locked.business, pin_lookup=pin_lookup(locked.business_id, value), is_active=True)
            .first()
        )
        if staff is None:
            locked.failed_pin_attempts += 1
            if locked.failed_pin_attempts >= settings.PIN_MAX_ATTEMPTS:
                locked.pin_locked_until = now + timedelta(minutes=settings.PIN_LOCK_MINUTES)
                locked.failed_pin_attempts = 0
            locked.save(update_fields=["failed_pin_attempts", "pin_locked_until", "updated_at"])
            audit(locked.business, "auth.pin_failed", device=locked)
        else:
            if locked.failed_pin_attempts or locked.pin_locked_until:
                locked.failed_pin_attempts = 0
                locked.pin_locked_until = None
                locked.save(update_fields=["failed_pin_attempts", "pin_locked_until", "updated_at"])
    if staff is None:
        raise ApiError("Code PIN incorrect.", 401)
    raw, session = issue_session(staff, kind=StaffSession.PIN, device=device)
    return raw, staff, session


def set_staff_pin(staff: StaffMember, pin: str | None, *, actor: StaffMember) -> None:
    if pin in (None, ""):
        staff.pin_lookup = None
    else:
        value = validate_pin(pin)
        lookup = pin_lookup(staff.business_id, value)
        clash = StaffMember.objects.filter(business_id=staff.business_id, pin_lookup=lookup).exclude(pk=staff.pk)
        if clash.exists():
            raise ApiError("Ce code PIN est déjà utilisé par un autre employé.", 409)
        staff.pin_lookup = lookup
    staff.save(update_fields=["pin_lookup", "updated_at"])
    StaffSession.objects.filter(staff=staff, kind=StaffSession.PIN, revoked_at__isnull=True).update(
        revoked_at=timezone.now()
    )
    audit(staff.business, "staff.pin_changed", actor=actor, target=staff)


def revoke_device(device: Device, *, actor: StaffMember) -> None:
    now = timezone.now()
    device.revoked_at = now
    device.save(update_fields=["revoked_at", "updated_at"])
    StaffSession.objects.filter(device=device, revoked_at__isnull=True).update(revoked_at=now)
    audit(device.business, "device.revoked", actor=actor, target=device)


def set_discount_code(business_settings: BusinessSettings, code: str) -> None:
    code = (code or "").strip()
    business_settings.discount_approval_code_hash = make_password(code) if code else ""
    business_settings.save(update_fields=["discount_approval_code_hash", "updated_at"])


def check_discount_code(business_settings: BusinessSettings, code: str) -> bool:
    stored = business_settings.discount_approval_code_hash
    return bool(stored and code) and check_password(code.strip(), stored)


def set_usd_rate(business: Business, rate: Decimal, *, actor: StaffMember | None) -> ExchangeRate:
    if rate <= 0 or rate > 100000:
        raise ApiError("Indiquez un taux valide (gourdes pour 1 dollar).")
    business_settings = business.settings
    business_settings.usd_rate = rate
    business_settings.save(update_fields=["usd_rate", "updated_at"])
    entry = ExchangeRate.objects.create(business=business, rate=rate, set_by=actor)
    audit(business, "settings.usd_rate", actor=actor, rate=str(rate))
    return entry

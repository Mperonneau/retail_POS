from __future__ import annotations

from datetime import timedelta

from django.utils import timezone
from rest_framework import authentication, exceptions

from apps.common.exceptions import ApiError

from .firebase import verify_id_token
from .models import Device, StaffMember, StaffSession
from .security import hash_token

SEEN_REFRESH = timedelta(minutes=5)


def _scheme_token(request, scheme: str) -> str | None:
    header = authentication.get_authorization_header(request).decode("latin-1").strip()
    if not header:
        return None
    parts = header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != scheme.lower():
        return None
    return parts[1].strip()


class StaffTokenAuthentication(authentication.BaseAuthentication):
    """`Authorization: Staff <token>` from a PIN unlock or an owner login."""

    keyword = "Staff"

    def authenticate(self, request):
        token = _scheme_token(request, self.keyword)
        if token is None:
            return None
        session = (
            StaffSession.objects.select_related("staff__business__settings", "device__location", "business")
            .filter(token_hash=hash_token(token))
            .first()
        )
        if session is None or not session.is_valid():
            raise exceptions.AuthenticationFailed("Votre session a expiré. Entrez votre code PIN.")
        staff = session.staff
        if not staff.is_active or not session.business.is_active:
            raise exceptions.AuthenticationFailed("Ce compte est désactivé.")
        if session.device_id and session.device.is_revoked:
            raise exceptions.AuthenticationFailed("Cet appareil a été déconnecté de la boutique.")
        now = timezone.now()
        if now - session.last_seen_at > SEEN_REFRESH:
            StaffSession.objects.filter(pk=session.pk).update(last_seen_at=now)
        return staff, session

    def authenticate_header(self, request):
        return self.keyword


class FirebaseIdentity:
    """A verified Firebase user who may not belong to any business yet."""

    is_authenticated = True
    is_anonymous = False
    business = None

    def __init__(self, claims: dict):
        self.uid = claims["uid"]
        self.email = claims.get("email", "")
        self.phone_number = claims.get("phone_number", "")
        self.pk = f"firebase:{self.uid}"


class FirebaseIdentityAuthentication(authentication.BaseAuthentication):
    """`Authorization: Bearer <Firebase ID token>`, used to register and sign in."""

    def authenticate(self, request):
        token = _scheme_token(request, "Bearer")
        if token is None:
            return None
        try:
            claims = verify_id_token(token)
        except ApiError as exc:
            raise exceptions.AuthenticationFailed(exc.message) from exc
        return FirebaseIdentity(claims), None

    def authenticate_header(self, request):
        return "Bearer"


class FirebaseStaffAuthentication(authentication.BaseAuthentication):
    """Firebase token straight on API calls (owner dashboard, no PIN step).

    `X-Business-Id` picks the business when one login belongs to several.
    """

    def authenticate(self, request):
        token = _scheme_token(request, "Bearer")
        if token is None:
            return None
        try:
            claims = verify_id_token(token)
        except ApiError as exc:
            raise exceptions.AuthenticationFailed(exc.message) from exc
        staff = resolve_firebase_staff(claims["uid"], request.headers.get("X-Business-Id"))
        return staff, None

    def authenticate_header(self, request):
        return "Bearer"


def resolve_firebase_staff(uid: str, business_id: str | None) -> StaffMember:
    rows = StaffMember.objects.select_related("business__settings").filter(
        firebase_uid=uid, is_active=True, business__is_active=True
    )
    if business_id:
        rows = rows.filter(business_id=business_id)
    members = list(rows[:2])
    if not members:
        raise exceptions.AuthenticationFailed("Aucune boutique n'est liée à ce compte.")
    if len(members) > 1:
        raise exceptions.AuthenticationFailed("Choisissez la boutique (en-tête X-Business-Id).")
    return members[0]


class DevicePrincipal:
    is_authenticated = True
    is_anonymous = False

    def __init__(self, device: Device):
        self.device = device
        self.business = device.business
        self.pk = f"device:{device.pk}"


class DeviceTokenAuthentication(authentication.BaseAuthentication):
    """`Authorization: Device <token>` for a paired register before any PIN."""

    keyword = "Device"

    def authenticate(self, request):
        token = _scheme_token(request, self.keyword)
        if token is None:
            return None
        device = (
            Device.objects.select_related("business__settings", "location")
            .filter(token_hash=hash_token(token))
            .first()
        )
        if device is None or device.is_revoked or not device.business.is_active:
            raise exceptions.AuthenticationFailed("Cet appareil n'est plus jumelé. Demandez un nouveau code.")
        return DevicePrincipal(device), device

    def authenticate_header(self, request):
        return self.keyword

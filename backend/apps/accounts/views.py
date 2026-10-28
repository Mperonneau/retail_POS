from __future__ import annotations

from decimal import Decimal, InvalidOperation

from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.views import TenantModelViewSet, TenantScopedMixin

from . import roles, services
from .authentication import DeviceTokenAuthentication, FirebaseIdentityAuthentication, resolve_firebase_staff
from .models import Device, DeviceInvite, ExchangeRate, Location, StaffMember, StaffSession
from .permissions import ActionPermission, IsFirebaseIdentity, IsPairedDevice, require
from .serializers import (
    BusinessSerializer,
    BusinessSettingsSerializer,
    DeviceInviteSerializer,
    DeviceSerializer,
    ExchangeRateSerializer,
    LocationSerializer,
    StaffMemberSerializer,
    StaffRosterSerializer,
    session_payload,
)


class RegisterView(APIView):
    """First sign-up: a Firebase user creates the business and becomes its owner."""

    authentication_classes = [FirebaseIdentityAuthentication]
    permission_classes = [IsFirebaseIdentity]

    def post(self, request):
        identity = request.user
        if StaffMember.objects.filter(firebase_uid=identity.uid, role=roles.OWNER).exists() and not request.data.get(
            "additional_business"
        ):
            raise ApiError("Ce compte possède déjà une boutique. Connectez-vous.", 409)
        data = request.data
        _business, staff = services.register_business(
            firebase_uid=identity.uid,
            business_name=str(data.get("business_name") or ""),
            owner_name=str(data.get("owner_name") or ""),
            email=str(data.get("email") or identity.email or ""),
            phone=str(data.get("phone") or identity.phone_number or ""),
            location_name=str(data.get("location_name") or ""),
            city=str(data.get("city") or ""),
            department=str(data.get("department") or ""),
        )
        token, session = services.issue_session(staff, kind=StaffSession.OWNER)
        return Response(session_payload(staff, token, session), status=status.HTTP_201_CREATED)


class OwnerSessionView(APIView):
    """Exchange a Firebase ID token for a Staff session (faster on slow links)."""

    authentication_classes = [FirebaseIdentityAuthentication]
    permission_classes = [IsFirebaseIdentity]

    def get(self, request):
        rows = StaffMember.objects.select_related("business").filter(
            firebase_uid=request.user.uid, is_active=True, business__is_active=True
        )
        return Response(
            {"businesses": [{"id": str(s.business_id), "name": s.business.name, "role": s.role} for s in rows]}
        )

    def post(self, request):
        staff = resolve_firebase_staff(request.user.uid, request.data.get("business_id"))
        token, session = services.issue_session(staff, kind=StaffSession.OWNER)
        audit(staff.business, "auth.owner_login", actor=staff, request=request)
        return Response(session_payload(staff, token, session))


class MeView(APIView):
    def get(self, request):
        staff = request.user
        session = request.auth if isinstance(request.auth, StaffSession) else None
        payload = session_payload(staff, "", session) if session else {
            "staff": {"id": str(staff.pk), "full_name": staff.full_name, "role": staff.role,
                      "permissions": staff.permissions},
            "business": BusinessSerializer(staff.business).data,
            "settings": BusinessSettingsSerializer(staff.business.settings).data,
        }
        payload.pop("token", None)
        return Response(payload)


class LogoutView(APIView):
    def post(self, request):
        if isinstance(request.auth, StaffSession):
            StaffSession.objects.filter(pk=request.auth.pk).update(revoked_at=timezone.now())
        return Response({"ok": True})


class PairDeviceView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_scope = "pair"

    def post(self, request):
        token, device = services.pair_device(
            code=str(request.data.get("code") or ""),
            device_name=str(request.data.get("device_name") or ""),
            platform=str(request.data.get("platform") or ""),
            app_version=str(request.data.get("app_version") or ""),
        )
        return Response(
            {
                "device_token": token,
                "token_type": "Device",
                "device": DeviceSerializer(device).data,
                "business": {"id": str(device.business_id), "name": device.business.name},
                "location_name": device.location.name,
                "paired_at": device.paired_at,
                "verified_at": device.last_verified_at,
                "offline_window_days": device.business.settings.offline_window_days,
            },
            status=status.HTTP_201_CREATED,
        )


class DeviceVerifyView(APIView):
    """Heartbeat that renews the offline PIN window and refreshes the roster."""

    authentication_classes = [DeviceTokenAuthentication]
    permission_classes = [IsPairedDevice]

    def post(self, request):
        device = services.verify_device(request.auth, app_version=str(request.data.get("app_version") or ""))
        business = device.business
        roster = StaffMember.objects.filter(business=business, is_active=True)
        return Response(
            {
                "verified_at": device.last_verified_at,
                "offline_window_days": business.settings.offline_window_days,
                "location_name": device.location.name,
                "business": {"id": str(business.pk), "name": business.name},
                "settings": BusinessSettingsSerializer(business.settings).data,
                "staff": StaffRosterSerializer(roster, many=True).data,
            }
        )


class PinUnlockView(APIView):
    authentication_classes = [DeviceTokenAuthentication]
    permission_classes = [IsPairedDevice]
    throttle_scope = "pin"

    def post(self, request):
        token, staff, session = services.unlock_with_pin(request.auth, str(request.data.get("pin") or ""))
        audit(staff.business, "auth.pin_login", actor=staff, device=request.auth, request=request)
        return Response(session_payload(staff, token, session))


class BusinessView(APIView):
    permission_classes = [require(roles.SETTINGS_ACCESS)]

    def get(self, request):
        return Response(BusinessSerializer(request.user.business).data)

    def patch(self, request):
        serializer = BusinessSerializer(request.user.business, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        audit(request.user.business, "business.updated", actor=request.user, request=request)
        return Response(serializer.data)


class BusinessSettingsView(APIView):
    def get_permissions(self):
        if self.request.method == "GET":
            return [ActionPermission()]
        return [require(roles.SETTINGS_ACCESS)()]

    def get(self, request):
        return Response(BusinessSettingsSerializer(request.user.business.settings).data)

    def patch(self, request):
        serializer = BusinessSettingsSerializer(request.user.business.settings, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        audit(request.user.business, "settings.updated", actor=request.user, request=request,
              fields=sorted(k for k in request.data.keys() if k != "discount_approval_code"))
        return Response(serializer.data)


class ExchangeRateView(APIView):
    def get_permissions(self):
        if self.request.method == "GET":
            return [ActionPermission()]
        return [require(roles.SETTINGS_ACCESS, roles.FINANCIAL_CASH)()]

    def get(self, request):
        rows = ExchangeRate.objects.filter(business=request.user.business).select_related("set_by")[:60]
        return Response({
            "current": request.user.business.settings.effective_usd_rate(),
            "history": ExchangeRateSerializer(rows, many=True).data,
        })

    def post(self, request):
        try:
            rate = Decimal(str(request.data.get("rate")))
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ApiError("Indiquez un taux valide (gourdes pour 1 dollar).") from exc
        entry = services.set_usd_rate(request.user.business, rate, actor=request.user)
        return Response(ExchangeRateSerializer(entry).data, status=status.HTTP_201_CREATED)


class DiscountCodeCheckView(APIView):
    throttle_scope = "pin"

    def post(self, request):
        ok = services.check_discount_code(request.user.business.settings, str(request.data.get("code") or ""))
        if not ok:
            raise ApiError("Code d'approbation incorrect.", 403)
        return Response({"approved": True})


class LocationViewSet(TenantModelViewSet):
    queryset = Location.objects.all()
    serializer_class = LocationSerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": None, "retrieve": None, "*": roles.SETTINGS_ACCESS}
    pagination_class = None

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])


class StaffViewSet(TenantModelViewSet):
    queryset = StaffMember.objects.select_related("business__settings")
    serializer_class = StaffMemberSerializer
    permission_classes = [ActionPermission]
    permission_map = {"roster": None, "*": roles.SETTINGS_ACCESS}
    filterset_fields = ["role", "is_active"]
    search_fields = ["full_name", "phone", "email"]
    pagination_class = None

    def perform_create(self, serializer):
        staff = serializer.save(business=self.request.user.business)
        pin = self.request.data.get("pin")
        if pin:
            services.set_staff_pin(staff, str(pin), actor=self.request.user)
        audit(staff.business, "staff.created", actor=self.request.user, target=staff, role=staff.role)

    def perform_update(self, serializer):
        staff = serializer.save()
        if not staff.is_active:
            StaffSession.objects.filter(staff=staff, revoked_at__isnull=True).update(revoked_at=timezone.now())
        audit(staff.business, "staff.updated", actor=self.request.user, target=staff,
              fields=sorted(self.request.data.keys()))

    def perform_destroy(self, instance):
        if instance.role == roles.OWNER:
            raise ApiError("Le compte du propriétaire ne peut pas être supprimé.")
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])
        StaffSession.objects.filter(staff=instance, revoked_at__isnull=True).update(revoked_at=timezone.now())
        audit(instance.business, "staff.deactivated", actor=self.request.user, target=instance)

    @action(detail=True, methods=["post"], url_path="set-pin")
    def set_pin(self, request, pk=None):
        staff = self.get_object()
        if staff.role in (roles.OWNER, roles.ADMIN) and request.user.role != roles.OWNER and staff != request.user:
            raise ApiError("Seul le propriétaire peut changer ce code PIN.", 403)
        services.set_staff_pin(staff, request.data.get("pin"), actor=request.user)
        return Response({"has_pin": staff.has_pin})

    @action(detail=False, methods=["get"])
    def roster(self, request):
        rows = self.get_queryset().filter(is_active=True)
        return Response(StaffRosterSerializer(rows, many=True).data)


class DeviceViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = Device.objects.select_related("location")
    serializer_class = DeviceSerializer
    permission_classes = [require(roles.SETTINGS_ACCESS)]
    pagination_class = None

    @action(detail=True, methods=["post"])
    def revoke(self, request, pk=None):
        device = self.get_object()
        services.revoke_device(device, actor=request.user)
        return Response(DeviceSerializer(device).data)

    @action(detail=False, methods=["get", "post"])
    def invites(self, request):
        if request.method == "GET":
            rows = DeviceInvite.objects.filter(
                business=request.user.business, used_at__isnull=True, expires_at__gt=timezone.now()
            )
            return Response(DeviceInviteSerializer(rows, many=True).data)
        location = None
        if request.data.get("location"):
            location = Location.objects.filter(business=request.user.business, pk=request.data["location"]).first()
            if location is None:
                raise ApiError("Point de vente introuvable.", 404)
        code, invite = services.create_device_invite(
            request.user, location=location, device_name=str(request.data.get("device_name") or "")
        )
        return Response({"code": code, **DeviceInviteSerializer(invite).data}, status=status.HTTP_201_CREATED)

from __future__ import annotations

from django.conf import settings
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts import roles
from apps.accounts.permissions import require
from apps.common.exceptions import ApiError
from apps.common.images import public_image_url, read_public_image

from . import services
from .models import StorefrontRequest


def _bearer(request) -> str:
    header = (request.headers.get("Authorization") or "").strip()
    return header[7:].strip() if header.lower().startswith("bearer ") else ""


def _shop_key(request) -> str:
    return (request.headers.get("X-Shop-Key") or "").strip()


def _keyed_shop(request):
    shop = services.shop_for_key(_shop_key(request))
    if shop is None:
        raise ApiError("Vitrine non publiée.", 404)
    return shop


class PublicView(APIView):
    """Vitrine endpoints. Shopper tokens are read by hand so a Bearer token
    is never mistaken for a staff Firebase token."""

    authentication_classes: list = []
    permission_classes = [AllowAny]


# --- Public browsing -------------------------------------------------------------------


class DirectoryView(PublicView):
    def get(self, request):
        return Response(services.directory(request.query_params.get("department") or ""))


class PublicShopView(PublicView):
    def get(self, request, slug: str):
        response = Response(services.public_shop(slug))
        response["Cache-Control"] = "public, max-age=30"
        return response


class PhotoView(PublicView):
    throttle_classes: list = []

    def get(self, request, name: str):
        content, mime = read_public_image(name)
        response = HttpResponse(content, content_type=mime)
        response["Cache-Control"] = "public, max-age=31536000, immutable"
        return response


class CreateRequestView(PublicView):
    throttle_scope = "storefront_order"

    def post(self, request, slug: str):
        services.release_expired(limit=50)
        account = services.account_for_token(_bearer(request), required=False)
        created = services.create_request(slug, request.data, account=account)
        return Response(services.public_view(services.get_request(created.pk)))


class RequestView(PublicView):
    def get(self, request, request_id: str):
        return Response(services.public_view(services.get_request(request_id)))


class CardIntentView(PublicView):
    throttle_scope = "storefront_pay"

    def post(self, request, request_id: str):
        return Response(services.card_intent(request_id))


class CardConfirmView(PublicView):
    throttle_scope = "storefront_pay"

    def post(self, request, request_id: str):
        paid = services.card_confirm(request_id, str(request.data.get("intent_id") or ""))
        return Response(services.public_view(paid))


class MonCashView(PublicView):
    throttle_scope = "storefront_pay"

    def post(self, request, request_id: str):
        return Response(services.moncash_start(request_id))

    def get(self, request, request_id: str):
        return Response(services.moncash_check(request_id))


# --- Shopper accounts ----------------------------------------------------------------


class AccountView(PublicView):
    def get(self, request):
        account = services.account_for_token(_bearer(request))
        return Response({"account": services.account_view(account)})

    def post(self, request):
        account = services.account_for_token(_bearer(request))
        return Response({"account": services.update_account(account, request.data.get("name"))})


class AccountOrdersView(PublicView):
    def get(self, request):
        return Response({"orders": services.account_orders(services.account_for_token(_bearer(request)))})


class AccountCodeView(PublicView):
    throttle_scope = "phone_code"

    def post(self, request):
        return Response(services.request_code(request.data.get("phone"), request.data.get("country")))


class AccountVerifyView(PublicView):
    throttle_scope = "phone_verify"

    def post(self, request):
        data = request.data
        return Response(services.verify_code(data.get("phone"), data.get("country"), data.get("code")))


class AccountRegisterView(PublicView):
    throttle_scope = "phone_verify"

    def post(self, request):
        data = request.data
        return Response(services.register_account(data.get("signup_token"), data.get("name"), data.get("email")))


class AccountLoginView(PublicView):
    throttle_scope = "pin"

    def post(self, request):
        data = request.data
        return Response(services.open_account(data.get("phone"), data.get("pin"), data.get("name")))


# --- Register with X-Shop-Key (current POS build) ----------------------------------------------


class LegacyPublishView(PublicView):
    def post(self, request):
        return Response(services.legacy_publish(_shop_key(request), request.data))


class LegacyShopRequestView(PublicView):
    def post(self, request):
        shop = services.shop_for_key(_shop_key(request))
        if shop is None:
            raise ApiError("Publiez d'abord la vitrine pour partager un lien.", 409)
        created = services.create_shop_request(shop, request.data)
        return Response(services.public_view(services.get_request(created.pk)))


class LegacyInboxView(PublicView):
    def get(self, request):
        return Response({"requests": services.inbox(_keyed_shop(request))})


class LegacySlugView(PublicView):
    def get(self, request):
        services.key_hash(_shop_key(request))
        shop = services.shop_for_key(_shop_key(request))
        return Response({"available": services.slug_available(request.query_params.get("slug") or "", shop)})


# --- Staff API ------------------------------------------------------------------------------------


def _shop_settings(shop) -> dict:
    return {
        "id": str(shop.pk),
        "slug": shop.slug or "",
        "name": shop.name,
        "phone": shop.phone,
        "address": shop.address,
        "city": shop.city,
        "department": shop.department,
        "categories": shop.categories,
        "description": shop.description,
        "pickup_note": shop.pickup_note,
        "cover_url": public_image_url(shop.cover),
        "enabled": shop.enabled,
        "paused": shop.paused,
        "accept_when_closed": shop.accept_when_closed,
        "open_hour": shop.open_hour,
        "close_hour": shop.close_hour,
        "closed_weekdays": shop.closed_weekdays,
        "usd_rate": float(shop.usd_rate),
        "effective_usd_rate": float(shop.effective_rate()),
        "has_shop_key": bool(shop.key_hash),
        "public_url": f"{settings.STOREFRONT_PUBLIC_URL.rstrip('/')}/{shop.slug}" if shop.slug else "",
        "published_at": shop.published_at,
        "availability": services.availability(shop),
    }


class StaffShopView(APIView):
    permission_classes = [require(roles.SETTINGS_ACCESS)]

    def get(self, request):
        return Response(_shop_settings(services.shop_for_business(request.user.business)))

    def patch(self, request):
        shop = services.shop_for_business(request.user.business)
        if request.data.get("enabled") and not shop.published_at:
            shop.published_at = timezone.now()
        missing: list[str] = []
        shop = services.apply_shop_settings(shop, request.data, missing)
        return Response({**_shop_settings(shop), "missing_photos": missing})

    put = patch


class StaffShopKeyView(APIView):
    permission_classes = [require(roles.SETTINGS_ACCESS)]

    def post(self, request):
        shop = services.shop_for_business(request.user.business)
        return Response({"shop_key": services.rotate_shop_key(shop)})


class StaffSlugView(APIView):
    permission_classes = [require(roles.SETTINGS_ACCESS)]

    def get(self, request):
        shop = services.shop_for_business(request.user.business)
        return Response({"available": services.slug_available(request.query_params.get("slug") or "", shop)})


class StaffRequestsView(APIView):
    permission_classes = [require(roles.TRANSACTIONS_OPERATE)]

    def get(self, request):
        shop = services.shop_for_business(request.user.business)
        rows = StorefrontRequest.objects.filter(shop=shop).select_related("shop", "order")
        for field in ("status", "kind", "source"):
            if request.query_params.get(field):
                rows = rows.filter(**{field: request.query_params[field]})
        if request.query_params.get("unimported") in ("1", "true"):
            rows = rows.filter(imported_at__isnull=True)
        return Response({"requests": [services.shop_view(r) for r in rows.order_by("-created_at")[:300]]})

    def post(self, request):
        shop = services.shop_for_business(request.user.business)
        created = services.create_shop_request(shop, request.data)
        return Response(services.shop_view(services.get_request(created.pk)), status=201)


class StaffRequestDetailView(APIView):
    permission_classes = [require(roles.TRANSACTIONS_OPERATE)]

    def _get(self, request, request_id):
        row = services.get_request(request_id)
        if row.business_id != request.user.business_id:
            raise ApiError("Ce lien n'existe pas ou a expiré.", 404)
        return row

    def get(self, request, request_id: str):
        return Response(services.shop_view(self._get(request, request_id)))

    def post(self, request, request_id: str, op: str):
        row = self._get(request, request_id)
        if op == "cancel":
            row = services.cancel_request(row, request.user)
        elif op == "ack":
            StorefrontRequest.objects.filter(pk=row.pk).update(imported_at=timezone.now())
        else:
            raise ApiError("Introuvable.", 404)
        return Response(services.shop_view(services.get_request(row.pk)))

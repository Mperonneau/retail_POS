from __future__ import annotations

import json

from django.conf import settings
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts import roles
from apps.accounts.permissions import ActionPermission, require
from apps.common.exceptions import ApiError
from apps.common.idempotency import idempotent
from apps.common.views import TenantScopedMixin

from . import services
from .models import PayLink
from .providers import moncash, stripe
from .serializers import PayLinkSerializer


def provider_config() -> dict:
    return {
        "stripe_configured": stripe.configured(),
        "moncash_configured": moncash.configured(),
        "publishable_key": settings.STRIPE_PUBLISHABLE_KEY,
        "currency": "usd",
        "platform_fee_bp": stripe.PLATFORM_PERCENT_BP,
        "platform_fee_fixed_cents": stripe.PLATFORM_FIXED_USD_CENTS,
        "stripe_percent_bp": stripe.STRIPE_PERCENT_BP,
        "stripe_fixed_cents": stripe.STRIPE_FIXED_USD_CENTS,
    }


class PayLinkViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = PayLink.objects.select_related("order")
    serializer_class = PayLinkSerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": None, "retrieve": None, "*": roles.TRANSACTIONS_OPERATE}
    filterset_fields = ["status", "customer", "order", "source"]
    search_fields = ["reference", "customer_name", "customer_phone"]

    @idempotent
    def create(self, request):
        link = services.create_paylink(request.user, request.data, request=request)
        return Response(PayLinkSerializer(link).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def refresh(self, request, pk=None):
        return Response(PayLinkSerializer(services.refresh_paylink(self.get_object())).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        return Response(PayLinkSerializer(services.cancel_paylink(request.user, self.get_object())).data)


def _cents(raw) -> int:
    try:
        return int(raw or 0)
    except (TypeError, ValueError) as exc:
        raise ApiError("Montant invalide.") from exc


class ConfigView(APIView):
    def get(self, request):
        return Response(provider_config())


class CardIntentView(APIView):
    """Card charge for the register's own card form (no Checkout page)."""

    permission_classes = [require(roles.TRANSACTIONS_OPERATE)]

    def post(self, request):
        result = stripe.create_payment_intent(
            reference=str(request.data.get("reference") or "").strip(),
            order_usd_cents=_cents(request.data.get("order_usd_cents")),
            description=str(request.data.get("description") or ""),
            metadata={"business": str(request.user.business_id)},
        )
        return Response({**result, "publishable_key": settings.STRIPE_PUBLISHABLE_KEY})

    def get(self, request, intent_id: str):
        return Response(stripe.retrieve_payment_intent(intent_id))


class MonCashView(APIView):
    permission_classes = [require(roles.TRANSACTIONS_OPERATE)]

    def post(self, request):
        return Response(moncash.create_payment(str(request.data.get("order_id") or ""),
                                               _cents(request.data.get("amount_htg"))))

    def get(self, request, order_id: str):
        return Response(moncash.payment_status(order_id))


class StripeWebhookView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes: list = []

    def post(self, request):
        secret = settings.STRIPE_WEBHOOK_SECRET
        if not secret:
            raise ApiError("Webhook Stripe non configuré. Ajoutez STRIPE_WEBHOOK_SECRET.", 503)
        payload = request.body
        if not stripe.verify_signature(payload, request.headers.get("Stripe-Signature") or "", secret):
            raise ApiError("Signature Stripe invalide.")
        try:
            event = json.loads(payload.decode() or "{}")
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise ApiError("Événement illisible.") from exc
        if not isinstance(event, dict):
            raise ApiError("Événement illisible.")
        return Response(services.handle_stripe_event(event))

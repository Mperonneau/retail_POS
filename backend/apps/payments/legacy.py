"""The payments server's routes, same paths and payloads.

The register calls these today without an account. They stay open while
LEGACY_PAYMENTS_OPEN is on, throttled per IP, and close once the apps sign in.
"""

from __future__ import annotations

from django.conf import settings
from django.http import HttpResponse
from django.utils.html import escape
from rest_framework.permissions import AllowAny, BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from .providers import moncash, stripe
from .services import public_origin
from .views import _cents, provider_config


class LegacyOpen(BasePermission):
    message = "Connexion requise."

    def has_permission(self, request, view):
        return bool(settings.LEGACY_PAYMENTS_OPEN) or bool(getattr(request.user, "is_authenticated", False))


class LegacyView(APIView):
    permission_classes = [LegacyOpen]
    throttle_scope = "legacy_payments"


class HealthView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({"ok": True})


class LegacyConfigView(LegacyView):
    def get(self, request):
        return Response(provider_config())


class LegacyCheckoutView(LegacyView):
    def post(self, request):
        body = request.data
        return Response(stripe.create_checkout(
            reference=str(body.get("reference") or "").strip(),
            order_usd_cents=_cents(body.get("order_usd_cents")),
            description=str(body.get("description") or ""),
            recipient_name=str(body.get("recipient_name") or ""),
            recipient_email=str(body.get("recipient_email") or ""),
            recipient_phone=str(body.get("recipient_phone") or ""),
            origin=public_origin(request),
        ))

    def get(self, request, session_id: str):
        return Response(stripe.retrieve_checkout(session_id))


class LegacyIntentView(LegacyView):
    def post(self, request):
        body = request.data
        return Response(stripe.create_payment_intent(
            reference=str(body.get("reference") or "").strip(),
            order_usd_cents=_cents(body.get("order_usd_cents")),
            description=str(body.get("description") or ""),
        ))

    def get(self, request, intent_id: str):
        return Response(stripe.retrieve_payment_intent(intent_id))


class LegacyMonCashView(LegacyView):
    def post(self, request):
        return Response(moncash.create_payment(str(request.data.get("order_id") or ""),
                                               _cents(request.data.get("amount_htg"))))

    def get(self, request, order_id: str):
        return Response(moncash.payment_status(order_id))


def _page(title: str, body: str) -> HttpResponse:
    html = ("<!doctype html><meta charset=utf-8>"
            f"<title>{escape(title)}</title>"
            "<body style=\"font-family:sans-serif;padding:32px\">"
            f"<h1>{escape(title)}</h1><p>{escape(body)}</p></body>")
    return HttpResponse(html, content_type="text/html; charset=utf-8")


def paid_page(request):
    return _page("Paiement reçu", "Vous pouvez fermer cette page et revenir à la caisse.")


def cancel_page(request):
    return _page("Paiement annulé", "Aucun montant n'a été encaissé. Revenez à la caisse pour réessayer.")

"""Stripe over plain HTTPS (no SDK), ported from the payments server."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings

from .errors import PaymentError

STRIPE_API = "https://api.stripe.com/v1"
STRIPE_VERSION = "2026-09-30.endive"
PLATFORM_PERCENT_BP = 150
PLATFORM_FIXED_USD_CENTS = 100
STRIPE_PERCENT_BP = 290
STRIPE_FIXED_USD_CENTS = 30
MIN_CARD_CENTS = 50
HTTP_TIMEOUT_S = 20


def configured() -> bool:
    return bool(settings.STRIPE_SECRET_KEY)


def price_card_charge(order_usd_cents: int) -> dict[str, int]:
    """Shop keeps the order. Payer covers 1.5% + $1, then Stripe 2.9% + $0.30."""
    order = max(0, int(order_usd_cents))
    percent = (order * PLATFORM_PERCENT_BP + 5000) // 10000
    platform = percent + PLATFORM_FIXED_USD_CENTS
    desired = order + platform
    numerator = desired + STRIPE_FIXED_USD_CENTS
    denom = 10000 - STRIPE_PERCENT_BP
    total = (numerator * 10000 + denom - 1) // denom
    stripe_fee = max(0, total - desired)
    return {
        "order_usd_cents": order,
        "platform_fee_usd_cents": platform,
        "stripe_fee_usd_cents": stripe_fee,
        "total_usd_cents": total,
    }


def verify_signature(payload: bytes, header: str, secret: str, tolerance: int = 300) -> bool:
    if not payload or not header or not secret:
        return False
    timestamp = ""
    signatures: list[str] = []
    for part in header.split(","):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        if key.strip() == "t":
            timestamp = value.strip()
        elif key.strip() == "v1":
            signatures.append(value.strip())
    if not timestamp or not signatures:
        return False
    try:
        stamp = int(timestamp)
    except ValueError:
        return False
    if abs(int(time.time()) - stamp) > tolerance:
        return False
    signed = timestamp.encode() + b"." + payload
    expected = hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(expected, sig) for sig in signatures)


def _error_message(raw: bytes) -> str:
    try:
        body = json.loads(raw.decode() or "{}")
        err = body.get("error") if isinstance(body, dict) else None
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
    except (json.JSONDecodeError, UnicodeDecodeError):
        pass
    return "Stripe a refusé la demande."


def request(method: str, path: str, fields: list[tuple[str, str]] | None = None, idempotency_key: str = "") -> dict:
    secret = settings.STRIPE_SECRET_KEY
    if not secret:
        raise PaymentError(503, "Stripe n'est pas configuré. Ajoutez STRIPE_SECRET_KEY sur le serveur.")
    data = urllib.parse.urlencode(fields or []).encode()
    req = urllib.request.Request(f"{STRIPE_API}{path}", data=data if method != "GET" else None, method=method)
    token = base64.b64encode(f"{secret}:".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    req.add_header("Stripe-Version", STRIPE_VERSION)
    if method != "GET":
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    if idempotency_key:
        req.add_header("Idempotency-Key", idempotency_key[:255])
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as res:
            raw = res.read()
    except urllib.error.HTTPError as exc:
        raise PaymentError(exc.code or 502, _error_message(exc.read())) from exc
    except urllib.error.URLError as exc:
        raise PaymentError(502, f"Stripe est injoignable : {exc.reason}") from exc
    parsed = json.loads(raw.decode() or "{}")
    if not isinstance(parsed, dict):
        raise PaymentError(502, "Réponse Stripe illisible.")
    return parsed


def integration_identifier(reference: str) -> str:
    """Stable per reference so a retry reuses the same Checkout Session."""
    digest = hashlib.sha256(reference.encode() or b"retail").hexdigest()
    suffix = "".join(chr(ord("a") + int(char, 16) % 26) for char in digest[:8])
    return f"retail_pos_{suffix}"


def create_checkout(*, reference: str, order_usd_cents: int, description: str, recipient_name: str = "",
                    recipient_email: str = "", recipient_phone: str = "", origin: str, kind: str = "retail",
                    metadata: dict | None = None) -> dict:
    if order_usd_cents <= 0:
        raise PaymentError(400, "Le montant en dollars doit être supérieur à zéro.")
    pricing = price_card_charge(order_usd_cents)
    label = description.strip() or f"Vente {reference}".strip()
    fields: list[tuple[str, str]] = [
        ("mode", "payment"),
        ("success_url", f"{origin}/paid?session_id={{CHECKOUT_SESSION_ID}}"),
        ("cancel_url", f"{origin}/cancel"),
        ("client_reference_id", reference[:200] or "retail"),
        ("integration_identifier", integration_identifier(reference or "retail")),
        ("line_items[0][quantity]", "1"),
        ("line_items[0][price_data][currency]", "usd"),
        ("line_items[0][price_data][unit_amount]", str(pricing["order_usd_cents"])),
        ("line_items[0][price_data][product_data][name]", label[:120]),
        ("line_items[1][quantity]", "1"),
        ("line_items[1][price_data][currency]", "usd"),
        ("line_items[1][price_data][unit_amount]", str(pricing["platform_fee_usd_cents"] + pricing["stripe_fee_usd_cents"])),
        ("line_items[1][price_data][product_data][name]", "Frais"),
        ("metadata[reference]", reference[:500]),
        ("metadata[order_usd_cents]", str(pricing["order_usd_cents"])),
        ("metadata[platform_fee_usd_cents]", str(pricing["platform_fee_usd_cents"])),
        ("metadata[stripe_fee_usd_cents]", str(pricing["stripe_fee_usd_cents"])),
        ("metadata[kind]", kind),
    ]
    for key, value in (metadata or {}).items():
        fields.append((f"metadata[{key}]", str(value)[:500]))
    if recipient_name:
        fields.append(("metadata[recipient_name]", recipient_name[:500]))
    if recipient_phone:
        fields.append(("metadata[recipient_phone]", recipient_phone[:100]))
    email = recipient_email.strip()
    if "@" in email and "." in email.split("@")[-1]:
        fields.append(("customer_email", email[:200]))
    session = request("POST", "/checkout/sessions", fields,
                      idempotency_key=f"retail-fee-{reference}-{pricing['total_usd_cents']}")
    url = str(session.get("url") or "")
    session_id = str(session.get("id") or "")
    if not url or not session_id:
        raise PaymentError(502, "Stripe n'a pas renvoyé de page de paiement.")
    return {"id": session_id, "url": url, **pricing}


def create_payment_intent(*, reference: str, order_usd_cents: int, description: str, kind: str = "retail_card",
                          metadata: dict | None = None) -> dict:
    if order_usd_cents <= 0:
        raise PaymentError(400, "Le montant en dollars doit être supérieur à zéro.")
    pricing = price_card_charge(order_usd_cents)
    label = description.strip() or f"Vente {reference}".strip()
    fields: list[tuple[str, str]] = [
        ("amount", str(pricing["total_usd_cents"])),
        ("currency", "usd"),
        # This API version rejects payment_method_types; card-only is an allow-list.
        ("allowed_payment_method_types[]", "card"),
        ("description", label[:500]),
        ("metadata[reference]", (reference or "retail")[:500]),
        ("metadata[order_usd_cents]", str(pricing["order_usd_cents"])),
        ("metadata[platform_fee_usd_cents]", str(pricing["platform_fee_usd_cents"])),
        ("metadata[stripe_fee_usd_cents]", str(pricing["stripe_fee_usd_cents"])),
        ("metadata[kind]", kind),
    ]
    for key, value in (metadata or {}).items():
        fields.append((f"metadata[{key}]", str(value)[:500]))
    intent = request("POST", "/payment_intents", fields,
                     idempotency_key=f"retail-card-{reference}-{pricing['total_usd_cents']}")
    intent_id = str(intent.get("id") or "")
    client_secret = str(intent.get("client_secret") or "")
    if not intent_id or not client_secret:
        raise PaymentError(502, "Stripe n'a pas renvoyé de paiement.")
    return {"id": intent_id, "client_secret": client_secret, **pricing}


def fetch_payment_intent(intent_id: str) -> dict:
    if not intent_id.startswith("pi_") or "/" in intent_id:
        raise PaymentError(400, "Paiement Stripe inconnu.")
    return request("GET", f"/payment_intents/{urllib.parse.quote(intent_id)}")


def retrieve_payment_intent(intent_id: str) -> dict:
    intent = fetch_payment_intent(intent_id)
    status = str(intent.get("status") or "")
    return {"id": intent_id, "status": status, "paid": status == "succeeded"}


def fetch_checkout(session_id: str) -> dict:
    if not session_id or "/" in session_id:
        raise PaymentError(400, "Session Stripe inconnue.")
    return request("GET", f"/checkout/sessions/{urllib.parse.quote(session_id)}")


def retrieve_checkout(session_id: str) -> dict:
    session = fetch_checkout(session_id)
    payment_status = str(session.get("payment_status") or "")
    return {
        "id": session_id,
        "payment_status": payment_status,
        "status": str(session.get("status") or ""),
        "paid": payment_status == "paid",
        "url": str(session.get("url") or ""),
    }

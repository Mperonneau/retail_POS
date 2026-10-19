"""Retail POS payments server.

Holds Stripe and MonCash secrets in the environment. The Flutter app calls
this process; it never sees `STRIPE_SECRET_KEY` or `MONCASH_SECRET`.

Env:
  STRIPE_SECRET_KEY       sk_… or rk_… (required for card and payment links)
  STRIPE_WEBHOOK_SECRET   whsec_… (required before launch; verifies webhooks)
  STRIPE_PUBLISHABLE_KEY  pk_… (required for the in-app card form)
  MONCASH_CLIENT_ID
  MONCASH_SECRET
  MONCASH_BASE_URL        default https://moncashbutton.digicelgroup.com
  PUBLIC_BASE_URL         success/cancel pages (Render sets RENDER_EXTERNAL_URL)
  STOREFRONT_DATA_DIR     vitrine catalog, requests and photos (default ./.data)
  DAY_USD_RATE            HTG per USD when a shop has no rate (default 135)
  PORT                    default 8787
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from storefront import StorefrontError, StorefrontStore

STRIPE_API = "https://api.stripe.com/v1"
STRIPE_VERSION = "2026-09-30.endive"
PLATFORM_PERCENT_BP = 150
PLATFORM_FIXED_USD_CENTS = 100
STRIPE_PERCENT_BP = 290
STRIPE_FIXED_USD_CENTS = 30
HTTP_TIMEOUT_S = 20

_token_lock = threading.Lock()
_token_cache: dict[str, tuple[str, float]] = {}


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


def verify_stripe_signature(payload: bytes, header: str, secret: str, tolerance: int = 300) -> bool:
    if not payload or not header or not secret:
        return False
    timestamp = ""
    signatures: list[str] = []
    for part in header.split(","):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key == "t":
            timestamp = value
        elif key == "v1":
            signatures.append(value)
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


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def stripe_configured() -> bool:
    return bool(_env("STRIPE_SECRET_KEY"))


def moncash_configured() -> bool:
    return bool(_env("MONCASH_CLIENT_ID") and _env("MONCASH_SECRET"))


def moncash_base() -> str:
    return (_env("MONCASH_BASE_URL") or "https://moncashbutton.digicelgroup.com").rstrip("/")


def public_base(host_header: str) -> str:
    explicit = _env("PUBLIC_BASE_URL") or _env("RENDER_EXTERNAL_URL")
    if explicit:
        return explicit.rstrip("/")
    host = (host_header or "localhost").strip()
    return f"http://{host}"


def _form(fields: list[tuple[str, str]]) -> bytes:
    return urllib.parse.urlencode(fields).encode()


def stripe_request(method: str, path: str, fields: list[tuple[str, str]] | None = None, idempotency_key: str = "") -> dict:
    secret = _env("STRIPE_SECRET_KEY")
    if not secret:
        raise PaymentError(503, "Stripe n'est pas configuré. Ajoutez STRIPE_SECRET_KEY sur le serveur.")
    data = _form(fields or [])
    req = urllib.request.Request(
        f"{STRIPE_API}{path}",
        data=data if method != "GET" else None,
        method=method,
    )
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
        detail = _stripe_error(exc.read())
        raise PaymentError(exc.code or 502, detail) from exc
    except urllib.error.URLError as exc:
        raise PaymentError(502, f"Stripe est injoignable : {exc.reason}") from exc
    parsed = json.loads(raw.decode() or "{}")
    if not isinstance(parsed, dict):
        raise PaymentError(502, "Réponse Stripe illisible.")
    return parsed


def _stripe_error(raw: bytes) -> str:
    try:
        body = json.loads(raw.decode() or "{}")
        err = body.get("error") if isinstance(body, dict) else None
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
    except (json.JSONDecodeError, UnicodeDecodeError):
        pass
    return "Stripe a refusé la demande."


def integration_identifier(reference: str) -> str:
    """Stable per reference so a retry reuses the same Checkout Session."""
    digest = hashlib.sha256(reference.encode() or b"retail").hexdigest()
    suffix = "".join(chr(ord("a") + int(char, 16) % 26) for char in digest[:8])
    return f"retail_pos_{suffix}"


def create_checkout(
    *,
    reference: str,
    order_usd_cents: int,
    description: str,
    recipient_name: str,
    recipient_email: str,
    recipient_phone: str,
    origin: str,
) -> dict:
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
        (
            "line_items[1][price_data][unit_amount]",
            str(pricing["platform_fee_usd_cents"] + pricing["stripe_fee_usd_cents"]),
        ),
        ("line_items[1][price_data][product_data][name]", "Frais"),
        ("metadata[reference]", reference[:500]),
        ("metadata[order_usd_cents]", str(pricing["order_usd_cents"])),
        ("metadata[platform_fee_usd_cents]", str(pricing["platform_fee_usd_cents"])),
        ("metadata[stripe_fee_usd_cents]", str(pricing["stripe_fee_usd_cents"])),
        ("metadata[kind]", "retail"),
    ]
    if recipient_name:
        fields.append(("metadata[recipient_name]", recipient_name[:500]))
    if recipient_phone:
        fields.append(("metadata[recipient_phone]", recipient_phone[:100]))
    email = recipient_email.strip()
    if "@" in email and "." in email.split("@")[-1]:
        fields.append(("customer_email", email[:200]))
    session = stripe_request(
        "POST",
        "/checkout/sessions",
        fields,
        idempotency_key=f"retail-fee-{reference}-{pricing['total_usd_cents']}",
    )
    url = str(session.get("url") or "")
    session_id = str(session.get("id") or "")
    if not url or not session_id:
        raise PaymentError(502, "Stripe n'a pas renvoyé de page de paiement.")
    return {"id": session_id, "url": url, **pricing}


def create_payment_intent(
    *,
    reference: str,
    order_usd_cents: int,
    description: str,
    kind: str = "retail_card",
) -> dict:
    """PaymentIntent for the in-app card form. The client confirms with Stripe.js."""
    if order_usd_cents <= 0:
        raise PaymentError(400, "Le montant en dollars doit être supérieur à zéro.")
    pricing = price_card_charge(order_usd_cents)
    label = description.strip() or f"Vente {reference}".strip()
    fields: list[tuple[str, str]] = [
        ("amount", str(pricing["total_usd_cents"])),
        ("currency", "usd"),
        # This API version rejects payment_method_types. Card-only is expressed
        # as an allow-list; the dashboard still filters incompatible methods.
        ("allowed_payment_method_types[]", "card"),
        ("description", label[:500]),
        ("metadata[reference]", (reference or "retail")[:500]),
        ("metadata[order_usd_cents]", str(pricing["order_usd_cents"])),
        ("metadata[platform_fee_usd_cents]", str(pricing["platform_fee_usd_cents"])),
        ("metadata[stripe_fee_usd_cents]", str(pricing["stripe_fee_usd_cents"])),
        ("metadata[kind]", kind),
    ]
    intent = stripe_request(
        "POST",
        "/payment_intents",
        fields,
        idempotency_key=f"retail-card-{reference}-{pricing['total_usd_cents']}",
    )
    intent_id = str(intent.get("id") or "")
    client_secret = str(intent.get("client_secret") or "")
    if not intent_id or not client_secret:
        raise PaymentError(502, "Stripe n'a pas renvoyé de paiement.")
    return {"id": intent_id, "client_secret": client_secret, **pricing}


def fetch_payment_intent(intent_id: str) -> dict:
    if not intent_id.startswith("pi_") or "/" in intent_id:
        raise PaymentError(400, "Paiement Stripe inconnu.")
    return stripe_request("GET", f"/payment_intents/{urllib.parse.quote(intent_id)}")


def retrieve_payment_intent(intent_id: str) -> dict:
    intent = fetch_payment_intent(intent_id)
    status = str(intent.get("status") or "")
    return {"id": intent_id, "status": status, "paid": status == "succeeded"}


def retrieve_checkout(session_id: str) -> dict:
    if not session_id or "/" in session_id:
        raise PaymentError(400, "Session Stripe inconnue.")
    session = stripe_request("GET", f"/checkout/sessions/{urllib.parse.quote(session_id)}")
    payment_status = str(session.get("payment_status") or "")
    return {
        "id": session_id,
        "payment_status": payment_status,
        "status": str(session.get("status") or ""),
        "paid": payment_status == "paid",
        "url": str(session.get("url") or ""),
    }


def moncash_token(force: bool = False) -> str:
    if not moncash_configured():
        raise PaymentError(
            503,
            "MonCash n'est pas configuré. Ajoutez MONCASH_CLIENT_ID et MONCASH_SECRET.",
        )
    client_id = _env("MONCASH_CLIENT_ID")
    secret = _env("MONCASH_SECRET")
    cache_key = f"{moncash_base()}|{client_id}"
    now = time.time()
    with _token_lock:
        cached = _token_cache.get(cache_key)
        if not force and cached and cached[1] - 10 > now:
            return cached[0]
    url = f"{moncash_base()}/Api/oauth/token"
    data = urllib.parse.urlencode({"scope": "read,write", "grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    basic = base64.b64encode(f"{client_id}:{secret}".encode()).decode()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Accept", "application/json")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as res:
            body = json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        raise PaymentError(exc.code or 502, "Identifiants MonCash refusés par Digicel.") from exc
    except urllib.error.URLError as exc:
        raise PaymentError(502, f"MonCash est injoignable : {exc.reason}") from exc
    token = str((body or {}).get("access_token") or "").strip()
    if not token:
        raise PaymentError(502, "Réponse OAuth MonCash sans access_token.")
    expires_in = int((body or {}).get("expires_in") or 59)
    with _token_lock:
        _token_cache[cache_key] = (token, now + max(expires_in, 30))
    return token


def moncash_post(path: str, payload: dict, *, retry: bool = True) -> dict:
    token = moncash_token()
    url = f"{moncash_base()}/Api{path}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as res:
            body = json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        if exc.code == 401 and retry:
            moncash_token(force=True)
            return moncash_post(path, payload, retry=False)
        raise PaymentError(exc.code or 502, _moncash_error(exc.read())) from exc
    except urllib.error.URLError as exc:
        raise PaymentError(502, f"MonCash est injoignable : {exc.reason}") from exc
    return body if isinstance(body, dict) else {}


def _moncash_error(raw: bytes) -> str:
    try:
        body = json.loads(raw.decode() or "{}")
        if isinstance(body, dict):
            detail = body.get("message") or body.get("error") or body.get("error_description")
            if detail:
                return str(detail)
    except (json.JSONDecodeError, UnicodeDecodeError):
        pass
    return "MonCash a refusé la demande."


def create_moncash(order_id: str, amount_htg: int) -> dict:
    amount = int(amount_htg)
    if amount < 1:
        raise PaymentError(400, "Le montant MonCash doit être d'au moins 1 HTG.")
    safe_id = "".join(ch for ch in order_id if ch.isalnum())[:24] or "retail"
    unique = f"{safe_id}{int(time.time())}"
    body = moncash_post("/v1/CreatePayment", {"amount": amount, "orderId": unique})
    token = ""
    payment_token = body.get("payment_token")
    if isinstance(payment_token, dict):
        token = str(payment_token.get("token") or "").strip()
    if not token:
        raise PaymentError(502, "Digicel n'a pas renvoyé de jeton de paiement.")
    quoted = urllib.parse.quote(token, safe="")
    url = f"{moncash_base()}/Moncash-middleware/Payment/Redirect?token={quoted}"
    return {"order_id": unique, "payment_url": url, "amount_htg": amount}


def moncash_paid(order_id: str) -> dict:
    safe_id = "".join(ch for ch in order_id if ch.isalnum())[:40]
    if not safe_id:
        raise PaymentError(400, "Commande MonCash inconnue.")
    try:
        body = moncash_post("/v1/RetrieveOrderPayment", {"orderId": safe_id})
    except PaymentError as exc:
        # Digicel answers this until the customer has actually paid.
        if "transaction not found" in exc.message.lower():
            return {
                "order_id": safe_id,
                "paid": False,
                "message": "pending",
                "transaction_id": "",
            }
        raise
    payment = body.get("payment") if isinstance(body, dict) else None
    message = ""
    txn = ""
    cost = 0
    if isinstance(payment, dict):
        message = str(payment.get("message") or "").strip().lower()
        txn = str(payment.get("transaction_id") or "")
        try:
            cost = int(round(float(payment.get("cost") or 0)))
        except (TypeError, ValueError):
            cost = 0
    paid = message in {"successful", "success", "succeeded"}
    return {
        "order_id": safe_id,
        "paid": paid,
        "message": message,
        "transaction_id": txn,
        "cost_htg": cost,
    }


class PaymentError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


STORE = StorefrontStore(
    _env("STOREFRONT_DATA_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".data")
)


def storefront_card_intent(request_id: str) -> dict:
    request = STORE.payable(request_id)
    order_cents = STORE.card_order_cents(request)
    if order_cents < 50:
        raise PaymentError(400, "Le montant est trop faible pour un paiement par carte.")
    shop = STORE.get_request(request_id)["shop"]
    intent = create_payment_intent(
        reference=request_id,
        order_usd_cents=order_cents,
        description=f"{shop.get('name') or 'Boutique'} · {request['number']}",
        kind="storefront",
    )
    STORE.attach(request_id, card_intent_id=intent["id"])
    return {**intent, "publishable_key": _env("STRIPE_PUBLISHABLE_KEY")}


def storefront_card_confirm(request_id: str, intent_id: str) -> dict:
    request = STORE.get_request(request_id)
    if request["status"] == "paid":
        return request
    intent = fetch_payment_intent(intent_id)
    return _settle_intent(request_id, intent)


def _settle_intent(request_id: str, intent: dict) -> dict:
    """Mark paid only when Stripe reports success for this request's amount."""
    request = STORE.get_request(request_id)
    if request["status"] == "paid":
        return request
    metadata = intent.get("metadata") or {}
    expected = price_card_charge(request["order_usd_cents"])["total_usd_cents"]
    if str(metadata.get("reference") or "") != request_id:
        raise PaymentError(400, "Ce paiement ne correspond pas à la demande.")
    if str(intent.get("status") or "") != "succeeded":
        raise PaymentError(402, "Le paiement par carte n'est pas confirmé.")
    received = int(intent.get("amount_received") or intent.get("amount") or 0)
    if received < expected:
        raise PaymentError(402, "Le montant reçu ne correspond pas au total.")
    return STORE.mark_paid(
        request_id,
        method="card",
        reference=str(intent.get("id") or ""),
        amount=received,
        currency="usd",
    )


def storefront_moncash_start(request_id: str) -> dict:
    request = STORE.payable(request_id)
    amount = STORE.moncash_amount(request)
    result = create_moncash(request_id, amount)
    STORE.attach(request_id, moncash_order_id=result["order_id"])
    return result


def storefront_moncash_status(request_id: str) -> dict:
    view = STORE.get_request(request_id)
    if view["status"] == "paid":
        return {"paid": True, "request": view}
    order_id = STORE.moncash_order_id(request_id)
    if not order_id:
        return {"paid": False, "request": view}
    status = moncash_paid(order_id)
    if not status["paid"]:
        return {"paid": False, "request": view}
    if status["cost_htg"] and status["cost_htg"] < view["moncash_htg"]:
        raise PaymentError(402, "Le montant MonCash reçu ne correspond pas au total.")
    view = STORE.mark_paid(
        request_id,
        method="moncash",
        reference=status["transaction_id"] or order_id,
        amount=status["cost_htg"] or view["moncash_htg"],
        currency="htg",
    )
    return {"paid": True, "request": view}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        # Avoid writing request bodies (they can carry payer contact).
        print(f"{self.address_string()} {self.command} {self.path} {args[1] if len(args) > 1 else ''}")

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Stripe-Signature, X-Shop-Key, Authorization",
        )
        self.send_header("Access-Control-Max-Age", "600")

    def _json(self, status: int, payload: dict) -> None:
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _html(self, status: int, title: str, body: str) -> None:
        page = (
            "<!doctype html><meta charset=utf-8>"
            f"<title>{title}</title>"
            "<body style=\"font-family:sans-serif;padding:32px\">"
            f"<h1>{title}</h1><p>{body}</p></body>"
        ).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def _bytes(self, status: int, raw: bytes, mime: str) -> None:
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        self.end_headers()
        self.wfile.write(raw)

    def _shop_key(self) -> str:
        return (self.headers.get("X-Shop-Key") or "").strip()

    def _bearer_optional(self) -> str:
        header = (self.headers.get("Authorization") or "").strip()
        if header.lower().startswith("bearer "):
            return header[7:].strip()
        return ""

    def _bearer(self) -> str:
        token = self._bearer_optional()
        if not token:
            raise StorefrontError(401, "Connexion requise.")
        return token

    def _read_json(self, max_bytes: int = 100_000) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > max_bytes:
            if length > max_bytes:
                self.close_connection = True
                raise PaymentError(413, "Envoi trop volumineux.")
            return {}
        raw = self.rfile.read(length)
        try:
            parsed = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        try:
            if path == "/health":
                self._json(200, {"ok": True})
            elif path == "/config":
                self._json(
                    200,
                    {
                        "stripe_configured": stripe_configured(),
                        "moncash_configured": moncash_configured(),
                        "publishable_key": _env("STRIPE_PUBLISHABLE_KEY"),
                        "currency": "usd",
                        "platform_fee_bp": PLATFORM_PERCENT_BP,
                        "platform_fee_fixed_cents": PLATFORM_FIXED_USD_CENTS,
                        "stripe_percent_bp": STRIPE_PERCENT_BP,
                        "stripe_fixed_cents": STRIPE_FIXED_USD_CENTS,
                    },
                )
            elif path.startswith("/payments/checkout/"):
                session_id = path.split("/")[-1]
                self._json(200, retrieve_checkout(session_id))
            elif path.startswith("/payments/intent/"):
                intent_id = path.split("/")[-1]
                self._json(200, retrieve_payment_intent(intent_id))
            elif path.startswith("/payments/moncash/"):
                order_id = path.split("/")[-1]
                self._json(200, moncash_paid(order_id))
            elif path.startswith("/storefront/"):
                self._storefront_get(path)
            elif path == "/paid":
                self._html(200, "Paiement reçu", "Vous pouvez fermer cette page et revenir à la caisse.")
            elif path == "/cancel":
                self._html(200, "Paiement annulé", "Aucun montant n'a été encaissé. Revenez à la caisse pour réessayer.")
            else:
                self._json(404, {"error": "Introuvable."})
        except (PaymentError, StorefrontError) as exc:
            self._json(exc.status, {"error": exc.message})

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        try:
            if path == "/payments/checkout":
                body = self._read_json()
                result = create_checkout(
                    reference=str(body.get("reference") or "").strip(),
                    order_usd_cents=int(body.get("order_usd_cents") or 0),
                    description=str(body.get("description") or ""),
                    recipient_name=str(body.get("recipient_name") or ""),
                    recipient_email=str(body.get("recipient_email") or ""),
                    recipient_phone=str(body.get("recipient_phone") or ""),
                    origin=public_base(self.headers.get("Host") or ""),
                )
                self._json(200, result)
            elif path == "/payments/intent":
                body = self._read_json()
                result = create_payment_intent(
                    reference=str(body.get("reference") or "").strip(),
                    order_usd_cents=int(body.get("order_usd_cents") or 0),
                    description=str(body.get("description") or ""),
                )
                self._json(200, result)
            elif path == "/payments/moncash":
                body = self._read_json()
                result = create_moncash(
                    str(body.get("order_id") or ""),
                    int(body.get("amount_htg") or 0),
                )
                self._json(200, result)
            elif path == "/payments/webhook":
                self._webhook()
            elif path.startswith("/storefront/"):
                self._storefront_post(path)
            else:
                self._json(404, {"error": "Introuvable."})
        except (PaymentError, StorefrontError) as exc:
            self._json(exc.status, {"error": exc.message})
        except (TypeError, ValueError):
            self._json(400, {"error": "Requête invalide."})

    def _storefront_get(self, path: str) -> None:
        parts = path.split("/")[2:]
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if parts == ["shops"]:
            department = (query.get("department") or [""])[0]
            self._json(200, STORE.directory(department))
        elif len(parts) == 2 and parts[0] == "shops":
            self._json(200, STORE.public_shop(parts[1]))
        elif len(parts) == 2 and parts[0] == "photos":
            raw, mime = STORE.read_photo(parts[1])
            self._bytes(200, raw, mime)
        elif len(parts) == 2 and parts[0] == "requests":
            self._json(200, STORE.get_request(parts[1]))
        elif len(parts) == 3 and parts[0] == "requests" and parts[2] == "moncash":
            self._json(200, storefront_moncash_status(parts[1]))
        elif parts == ["account"]:
            self._json(200, {"account": STORE.account_for_token(self._bearer())})
        elif parts == ["account", "orders"]:
            self._json(200, {"orders": STORE.account_orders(self._bearer())})
        elif parts == ["shop", "inbox"]:
            self._json(200, {"requests": STORE.inbox(self._shop_key())})
        elif parts == ["shop", "slug"]:
            slug = (query.get("slug") or [""])[0]
            self._json(200, {"available": STORE.slug_available(self._shop_key(), slug)})
        else:
            self._json(404, {"error": "Introuvable."})

    def _storefront_post(self, path: str) -> None:
        parts = path.split("/")[2:]
        if parts == ["shop", "publish"]:
            body = self._read_json(max_bytes=24_000_000)
            self._json(200, STORE.publish(self._shop_key(), body))
        elif parts == ["shop", "requests"]:
            self._json(200, STORE.create_shop_request(self._shop_key(), self._read_json()))
        elif parts == ["account", "code"]:
            body = self._read_json()
            self._json(200, STORE.request_code(body.get("phone"), body.get("country")))
        elif parts == ["account", "verify"]:
            body = self._read_json()
            self._json(200, STORE.verify_code(body.get("phone"), body.get("country"), body.get("code")))
        elif parts == ["account", "register"]:
            body = self._read_json()
            self._json(
                200,
                STORE.register_account(body.get("signup_token"), body.get("name"), body.get("email")),
            )
        elif parts == ["account", "login"]:
            body = self._read_json()
            self._json(200, STORE.open_account(body.get("phone"), body.get("pin"), body.get("name")))
        elif parts == ["account"]:
            body = self._read_json()
            self._json(200, {"account": STORE.update_account(self._bearer(), body.get("name"))})
        elif len(parts) == 3 and parts[0] == "shops" and parts[2] == "requests":
            token = self._bearer_optional()
            phone = STORE.phone_for_token(token) if token else ""
            self._json(200, STORE.create_request(parts[1], self._read_json(), account_phone=phone))
        elif len(parts) == 3 and parts[0] == "requests" and parts[2] == "card":
            self._json(200, storefront_card_intent(parts[1]))
        elif len(parts) == 4 and parts[0] == "requests" and parts[2:] == ["card", "confirm"]:
            body = self._read_json()
            self._json(200, storefront_card_confirm(parts[1], str(body.get("intent_id") or "")))
        elif len(parts) == 3 and parts[0] == "requests" and parts[2] == "moncash":
            self._json(200, storefront_moncash_start(parts[1]))
        else:
            self._json(404, {"error": "Introuvable."})

    def _webhook(self) -> None:
        secret = _env("STRIPE_WEBHOOK_SECRET")
        if not secret:
            self._json(
                503,
                {"error": "Webhook Stripe non configuré. Ajoutez STRIPE_WEBHOOK_SECRET."},
            )
            return
        length = int(self.headers.get("Content-Length") or 0)
        payload = self.rfile.read(length) if length else b""
        header = self.headers.get("Stripe-Signature") or ""
        if not verify_stripe_signature(payload, header, secret):
            self._json(400, {"error": "Signature Stripe invalide."})
            return
        try:
            event = json.loads(payload.decode() or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "Événement illisible."})
            return
        kind = str(event.get("type") or "")
        obj = ((event.get("data") or {}).get("object") or {}) if isinstance(event, dict) else {}
        if kind == "payment_intent.succeeded" and (obj.get("metadata") or {}).get("kind") == "storefront":
            request_id = str((obj.get("metadata") or {}).get("reference") or "")
            settled = False
            try:
                settled = _settle_intent(request_id, obj)["status"] == "paid"
            except (PaymentError, StorefrontError):
                settled = False
            self._json(200, {"received": True, "paid": settled})
            return
        payment_status = str(obj.get("payment_status") or "")
        accepted = kind in {
            "checkout.session.completed",
            "checkout.session.async_payment_succeeded",
        }
        # Fulfillment for the open register is the session retrieve. The
        # webhook is the source of truth when the cashier is no longer polling.
        # Record only paid (or no-longer-unpaid) sessions.
        paid = accepted and payment_status not in {"", "unpaid"}
        self._json(200, {"received": True, "paid": paid})


def main() -> None:
    port = int(os.environ.get("PORT") or "8787")
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"payments server listening on {port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

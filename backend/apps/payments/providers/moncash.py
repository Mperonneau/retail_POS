"""Digicel MonCash button API, ported from the payments server."""

from __future__ import annotations

import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings
from django.core.cache import cache

from .errors import PaymentError

HTTP_TIMEOUT_S = 20


def configured() -> bool:
    return bool(settings.MONCASH_CLIENT_ID and settings.MONCASH_SECRET)


def _base() -> str:
    return settings.MONCASH_BASE_URL


def token(force: bool = False) -> str:
    if not configured():
        raise PaymentError(503, "MonCash n'est pas configuré. Ajoutez MONCASH_CLIENT_ID et MONCASH_SECRET.")
    cache_key = f"moncash:token:{_base()}:{settings.MONCASH_CLIENT_ID}"
    if not force:
        cached = cache.get(cache_key)
        if cached:
            return cached
    data = urllib.parse.urlencode({"scope": "read,write", "grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(f"{_base()}/Api/oauth/token", data=data, method="POST")
    basic = base64.b64encode(f"{settings.MONCASH_CLIENT_ID}:{settings.MONCASH_SECRET}".encode()).decode()
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
    value = str((body or {}).get("access_token") or "").strip()
    if not value:
        raise PaymentError(502, "Réponse OAuth MonCash sans access_token.")
    expires_in = int((body or {}).get("expires_in") or 59)
    cache.set(cache_key, value, max(expires_in - 10, 20))
    return value


def _error_message(raw: bytes) -> str:
    try:
        body = json.loads(raw.decode() or "{}")
        if isinstance(body, dict):
            detail = body.get("message") or body.get("error") or body.get("error_description")
            if detail:
                return str(detail)
    except (json.JSONDecodeError, UnicodeDecodeError):
        pass
    return "MonCash a refusé la demande."


def post(path: str, payload: dict, *, retry: bool = True) -> dict:
    access = token()
    req = urllib.request.Request(f"{_base()}/Api{path}", data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {access}")
    req.add_header("Accept", "application/json")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as res:
            body = json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        if exc.code == 401 and retry:
            token(force=True)
            return post(path, payload, retry=False)
        raise PaymentError(exc.code or 502, _error_message(exc.read())) from exc
    except urllib.error.URLError as exc:
        raise PaymentError(502, f"MonCash est injoignable : {exc.reason}") from exc
    return body if isinstance(body, dict) else {}


def create_payment(order_id: str, amount_htg: int) -> dict:
    amount = int(amount_htg)
    if amount < 1:
        raise PaymentError(400, "Le montant MonCash doit être d'au moins 1 HTG.")
    safe_id = "".join(ch for ch in order_id if ch.isalnum())[:24] or "retail"
    unique = f"{safe_id}{int(time.time())}"
    body = post("/v1/CreatePayment", {"amount": amount, "orderId": unique})
    value = ""
    payment_token = body.get("payment_token")
    if isinstance(payment_token, dict):
        value = str(payment_token.get("token") or "").strip()
    if not value:
        raise PaymentError(502, "Digicel n'a pas renvoyé de jeton de paiement.")
    quoted = urllib.parse.quote(value, safe="")
    url = f"{_base()}/Moncash-middleware/Payment/Redirect?token={quoted}"
    return {"order_id": unique, "payment_url": url, "amount_htg": amount}


def payment_status(order_id: str) -> dict:
    safe_id = "".join(ch for ch in order_id if ch.isalnum())[:40]
    if not safe_id:
        raise PaymentError(400, "Commande MonCash inconnue.")
    try:
        body = post("/v1/RetrieveOrderPayment", {"orderId": safe_id})
    except PaymentError as exc:
        # Digicel answers this until the customer has actually paid.
        if "transaction not found" in exc.message.lower():
            return {"order_id": safe_id, "paid": False, "message": "pending", "transaction_id": "", "cost_htg": 0}
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
    return {
        "order_id": safe_id,
        "paid": message in {"successful", "success", "succeeded"},
        "message": message,
        "transaction_id": txn,
        "cost_htg": cost,
    }

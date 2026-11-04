"""Phone number checks for vitrine sign-in.

PHONE_VERIFICATION_BACKEND picks who sends the code:
  console  - the server makes a 6-digit code and logs it (development)
  twilio   - Twilio Verify sends and checks the SMS
  firebase - the app verifies with Firebase; `code` is the Firebase ID token
"""

from __future__ import annotations

import base64
import json
import logging
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from apps.accounts.security import hash_token
from apps.common.exceptions import ApiError

from .constants import LOGIN_COUNTRY
from .models import PhoneVerification

log = logging.getLogger(__name__)


def login_phone(phone: object, country: object) -> tuple[str, str, str]:
    """(iso, e164, digits) for a national number and the chosen country."""
    iso = str(country or "").strip().upper()
    row = LOGIN_COUNTRY.get(iso)
    if row is None:
        raise ApiError("Choisissez un pays.")
    _, dial, low, high, prefixes, _name = row
    national = re.sub(r"\D", "", str(phone or ""))
    if national.startswith(dial) and low <= len(national) - len(dial) <= high:
        national = national[len(dial):]
    if national.startswith("0") and low <= len(national) - 1 <= high:
        national = national[1:]
    if not (low <= len(national) <= high) or (prefixes and not national.startswith(prefixes)):
        raise ApiError("Indiquez un numéro de téléphone valide.")
    digits = f"{dial}{national}"
    if len(digits) > 15:
        raise ApiError("Indiquez un numéro de téléphone valide.")
    return iso, f"+{digits}", digits


def _twilio(path: str, fields: dict) -> dict:
    sid = settings.TWILIO_ACCOUNT_SID
    service = settings.TWILIO_VERIFY_SERVICE_SID
    if not (sid and settings.TWILIO_AUTH_TOKEN and service):
        raise ApiError("L'envoi de SMS n'est pas configuré.", 503)
    url = f"https://verify.twilio.com/v2/Services/{service}/{path}"
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(), method="POST")
    basic = base64.b64encode(f"{sid}:{settings.TWILIO_AUTH_TOKEN}".encode()).decode()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        if exc.code == 404 and path == "VerificationCheck":
            raise ApiError("Ce code a expiré. Demandez-en un nouveau.", 400) from exc
        raise ApiError("L'envoi du SMS a échoué. Réessayez.", 502) from exc
    except urllib.error.URLError as exc:
        raise ApiError("Le service SMS est injoignable.", 502) from exc


def send_code(phone: object, country: object) -> dict:
    iso, e164, digits = login_phone(phone, country)
    backend = settings.PHONE_VERIFICATION_BACKEND
    if settings.STOREFRONT_ACCEPT_ANY_CODE or backend == "firebase":
        return {"sent": True}
    expires = timezone.now() + timedelta(minutes=settings.PHONE_CODE_TTL_MINUTES)
    if backend == "twilio":
        _twilio("Verifications", {"To": e164, "Channel": "sms"})
        PhoneVerification.objects.create(phone_digits=digits, phone=e164, country=iso, expires_at=expires)
        return {"sent": True}
    code = f"{secrets.randbelow(1_000_000):06d}"
    PhoneVerification.objects.filter(phone_digits=digits, verified_at__isnull=True).delete()
    PhoneVerification.objects.create(phone_digits=digits, phone=e164, country=iso, expires_at=expires,
                                     code_hash=hash_token(f"{digits}:{code}"))
    log.info("Vitrine verification code for %s: %s", e164, code)
    return {"sent": True}


def check_code(phone: object, country: object, code: object) -> tuple[str, str, str]:
    """Raises unless the code proves the caller owns the number."""
    iso, e164, digits = login_phone(phone, country)
    value = str(code or "").strip()
    if not value:
        raise ApiError("Indiquez le code.")
    if settings.STOREFRONT_ACCEPT_ANY_CODE:
        return iso, e164, digits
    backend = settings.PHONE_VERIFICATION_BACKEND
    if backend == "firebase":
        from apps.accounts.firebase import verify_id_token

        claims = verify_id_token(value)
        if re.sub(r"\D", "", str(claims.get("phone_number") or "")) != digits:
            raise ApiError("Ce numéro n'a pas été vérifié.", 401)
        return iso, e164, digits
    pending = (PhoneVerification.objects.filter(phone_digits=digits, verified_at__isnull=True,
                                                expires_at__gt=timezone.now()).order_by("-created_at").first())
    if pending is None:
        raise ApiError("Ce code a expiré. Demandez-en un nouveau.")
    if pending.attempts >= settings.PHONE_CODE_MAX_ATTEMPTS:
        raise ApiError("Trop d'essais. Demandez un nouveau code.", 429)
    pending.attempts += 1
    if backend == "twilio":
        result = _twilio("VerificationCheck", {"To": e164, "Code": value})
        ok = str(result.get("status") or "") == "approved"
    else:
        ok = secrets.compare_digest(pending.code_hash, hash_token(f"{digits}:{value}"))
    if not ok:
        pending.save(update_fields=["attempts", "updated_at"])
        raise ApiError("Code incorrect.", 401)
    pending.verified_at = timezone.now()
    pending.save(update_fields=["attempts", "verified_at", "updated_at"])
    return iso, e164, digits

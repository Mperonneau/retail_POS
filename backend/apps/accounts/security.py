from __future__ import annotations

import hashlib
import hmac
import re
import secrets

from django.conf import settings

from apps.common.exceptions import ApiError

DEVICE_CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTUVWXYZ"
PIN_RE = re.compile(r"^\d{4}$")


def new_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(raw: str) -> str:
    return hashlib.sha256((raw or "").encode()).hexdigest()


def pin_lookup(business_id, pin: str) -> str:
    """Keyed digest so a PIN identifies one employee without a slow scan.

    A 4-digit PIN has only 10,000 values; the server-side pepper is what keeps
    a leaked database from revealing them.
    """
    message = f"{business_id}:{pin}".encode()
    return hmac.new(settings.PIN_PEPPER.encode(), message, hashlib.sha256).hexdigest()


def validate_pin(pin: object) -> str:
    value = str(pin or "").strip()
    if not PIN_RE.match(value):
        raise ApiError("Le code PIN doit avoir 4 chiffres.")
    return value


def generate_device_code() -> str:
    chars = [secrets.choice(DEVICE_CODE_ALPHABET) for _ in range(8)]
    return f"{''.join(chars[:4])}-{''.join(chars[4:])}"


def normalize_device_code(raw: str) -> str:
    """« abcd 1234 » → « ABCD-1234 ». O / I / L become 0 / 1 / 1, like the app."""
    out = []
    for ch in (raw or "").upper():
        mapped = {"O": "0", "I": "1", "L": "1"}.get(ch, ch)
        if re.match(r"[0-9A-Z]", mapped):
            out.append(mapped)
    body = "".join(out)[:8]
    if len(body) <= 4:
        return body
    return f"{body[:4]}-{body[4:]}"

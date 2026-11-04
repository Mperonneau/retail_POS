"""Firebase ID token verification.

Firebase is not configured yet. Until `FIREBASE_CREDENTIALS_JSON` is set,
development and tests accept `dev:<uid>[:<email>][:<phone>]` tokens.
"""

from __future__ import annotations

import json
import logging
import os
import threading

from django.conf import settings

from apps.common.exceptions import ApiError

logger = logging.getLogger(__name__)
_init_lock = threading.Lock()
_app = None


def firebase_configured() -> bool:
    return bool(settings.FIREBASE_CREDENTIALS_JSON)


def _firebase_app():
    global _app
    if _app is not None:
        return _app
    with _init_lock:
        if _app is not None:
            return _app
        import firebase_admin
        from firebase_admin import credentials

        raw = settings.FIREBASE_CREDENTIALS_JSON
        info = json.loads(raw) if raw.lstrip().startswith("{") else raw
        cred = credentials.Certificate(info if isinstance(info, dict) else os.fspath(info))
        options = {"projectId": settings.FIREBASE_PROJECT_ID} if settings.FIREBASE_PROJECT_ID else None
        _app = firebase_admin.initialize_app(cred, options, name="retail-pos")
        return _app


def verify_id_token(token: str) -> dict:
    """Return the token claims (`uid`, `email`, `phone_number`) or raise 401."""
    token = (token or "").strip()
    if not token:
        raise ApiError("Connexion requise.", 401)
    if token.startswith("dev:"):
        if not settings.FIREBASE_DEV_MODE:
            raise ApiError("Connexion refusée.", 401)
        parts = token.split(":")
        uid = parts[1] if len(parts) > 1 else ""
        if not uid:
            raise ApiError("Connexion refusée.", 401)
        return {
            "uid": uid,
            "email": parts[2] if len(parts) > 2 else "",
            "phone_number": parts[3] if len(parts) > 3 else "",
        }
    if not firebase_configured():
        raise ApiError("La connexion Firebase n'est pas encore configurée sur le serveur.", 503)
    from firebase_admin import auth

    try:
        claims = auth.verify_id_token(token, app=_firebase_app())
    except Exception as exc:  # firebase raises several unrelated exception types
        logger.info("Firebase token rejected: %s", exc.__class__.__name__)
        raise ApiError("Votre session a expiré. Reconnectez-vous.", 401) from exc
    return {
        "uid": claims.get("uid") or claims.get("sub") or "",
        "email": claims.get("email") or "",
        "phone_number": claims.get("phone_number") or "",
    }

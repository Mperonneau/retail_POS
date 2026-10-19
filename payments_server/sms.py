"""Send the vitrine login code by SMS.

Env (all required on the payments server before a code can leave the machine):
  TWILIO_ACCOUNT_SID
  TWILIO_AUTH_TOKEN
  TWILIO_FROM                    sending number, or
  TWILIO_MESSAGING_SERVICE_SID   Messaging Service instead of TWILIO_FROM
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request


class SmsError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        self.message = message
        super().__init__(message)


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def send_sms(e164: str, body: str) -> None:
    sink = _env("STOREFRONT_OTP_SINK")
    if sink:
        # Local checks only. Leave this unset on the host so a real SMS is required.
        previous: dict = {}
        try:
            with open(sink, encoding="utf-8") as fh:
                loaded = json.load(fh)
            if isinstance(loaded, dict):
                previous = loaded
        except (OSError, json.JSONDecodeError):
            previous = {}
        previous[e164] = body
        with open(sink, "w", encoding="utf-8") as fh:
            json.dump(previous, fh)
        return
    sid = _env("TWILIO_ACCOUNT_SID")
    token = _env("TWILIO_AUTH_TOKEN")
    sender = _env("TWILIO_FROM")
    service = _env("TWILIO_MESSAGING_SERVICE_SID")
    if not (sid and token and (sender or service)):
        raise SmsError(503, "L'envoi du code n'est pas encore configuré.")
    fields = [("To", e164), ("Body", body)]
    if service:
        fields.append(("MessagingServiceSid", service))
    else:
        fields.append(("From", sender))
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
        data=data,
        method="POST",
    )
    basic = base64.b64encode(f"{sid}:{token}".encode()).decode()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            res.read()
    except urllib.error.HTTPError as exc:
        print(f"sms: twilio HTTP {exc.code}", flush=True)
        raise SmsError(502, "Le code n'a pas pu être envoyé. Réessayez.") from exc
    except urllib.error.URLError as exc:
        print(f"sms: twilio injoignable ({exc.reason})", flush=True)
        raise SmsError(502, "Le code n'a pas pu être envoyé. Réessayez.") from exc

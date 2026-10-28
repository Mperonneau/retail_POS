from __future__ import annotations

import functools

from django.db import IntegrityError, transaction
from rest_framework.response import Response

from .models import IdempotencyRecord


def idempotent(view_method):
    """Replay the stored response when `Idempotency-Key` was already used.

    Registers on weak connections resend writes they never saw answered; the
    key makes the second attempt return the first result instead of charging twice.
    """

    @functools.wraps(view_method)
    def wrapper(self, request, *args, **kwargs):
        key = (request.headers.get("Idempotency-Key") or "").strip()[:100]
        business = getattr(getattr(request, "user", None), "business", None)
        if not key or business is None:
            return view_method(self, request, *args, **kwargs)
        existing = IdempotencyRecord.objects.filter(business=business, key=key).first()
        if existing:
            return Response(existing.body, status=existing.status_code, headers={"Idempotent-Replay": "true"})
        response = view_method(self, request, *args, **kwargs)
        if 200 <= response.status_code < 300 and isinstance(response.data, (dict, list)):
            try:
                with transaction.atomic():
                    IdempotencyRecord.objects.create(
                        business=business,
                        key=key,
                        endpoint=request.path[:200],
                        status_code=response.status_code,
                        body=_jsonable(response.data),
                    )
            except IntegrityError:
                pass
        return response

    return wrapper


def _jsonable(data):
    from rest_framework.utils.encoders import JSONEncoder
    import json

    return json.loads(json.dumps(data, cls=JSONEncoder))

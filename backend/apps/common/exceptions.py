from __future__ import annotations

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response


class ApiError(exceptions.APIException):
    """Business-rule failure with a French message the apps show as-is."""

    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = "Requête invalide."

    def __init__(self, message: str, status_code: int = 400, code: str = "invalid"):
        super().__init__(detail=message, code=code)
        self.status_code = status_code
        self.message = message


def _first_message(detail: object) -> str:
    if isinstance(detail, str):
        return detail
    if isinstance(detail, list) and detail:
        return _first_message(detail[0])
    if isinstance(detail, dict) and detail:
        key, value = next(iter(detail.items()))
        message = _first_message(value)
        if key in ("non_field_errors", "detail", "__all__"):
            return message
        return f"{key} : {message}"
    return "Requête invalide."


def api_exception_handler(exc, context):
    """Every error body has `error` (one readable sentence), like the old server."""
    if isinstance(exc, DjangoValidationError):
        exc = exceptions.ValidationError(exc.message_dict if hasattr(exc, "error_dict") else exc.messages)
    elif isinstance(exc, Http404):
        exc = exceptions.NotFound("Introuvable.")
    elif isinstance(exc, DjangoPermissionDenied):
        exc = exceptions.PermissionDenied()

    from rest_framework.views import exception_handler

    response = exception_handler(exc, context)
    if response is None:
        return None
    detail = response.data
    if isinstance(exc, exceptions.NotAuthenticated):
        message = "Connexion requise."
    elif isinstance(exc, exceptions.PermissionDenied) and str(exc.detail) == exceptions.PermissionDenied.default_detail:
        message = "Vous n'avez pas l'autorisation pour cette action."
    elif isinstance(exc, exceptions.Throttled):
        message = "Trop de tentatives. Patientez un instant puis réessayez."
    else:
        message = _first_message(detail)
    body = {"error": message}
    if isinstance(detail, dict) and not isinstance(exc, ApiError) and set(detail) != {"detail"}:
        body["fields"] = detail
    headers = {name: response[name] for name in ("Retry-After", "WWW-Authenticate") if response.has_header(name)}
    return Response(body, status=response.status_code, headers=headers)

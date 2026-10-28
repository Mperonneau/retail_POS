from __future__ import annotations

from apps.common.exceptions import ApiError

from .models import Location, StaffSession


def current_location(request, explicit_id=None) -> Location | None:
    """The register's own store, else the staff default, else the main store."""
    business = request.user.business
    if explicit_id:
        location = Location.objects.filter(business=business, pk=explicit_id).first()
        if location is None:
            raise ApiError("Point de vente introuvable.", 404)
        return location
    session = request.auth if isinstance(request.auth, StaffSession) else None
    if session is not None and session.device_id:
        return session.device.location
    if request.user.default_location_id:
        return request.user.default_location
    return Location.objects.filter(business=business, is_active=True).order_by("-is_default", "created_at").first()


def current_device(request):
    session = request.auth if isinstance(request.auth, StaffSession) else None
    return session.device if session is not None and session.device_id else None

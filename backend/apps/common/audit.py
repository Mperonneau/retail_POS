from __future__ import annotations

from .models import AuditEvent


def client_ip(request) -> str | None:
    if request is None:
        return None
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
    if forwarded:
        return forwarded.split(",")[0].strip() or None
    return request.META.get("REMOTE_ADDR") or None


def audit(business, action: str, *, actor=None, target=None, request=None, device=None, **data) -> None:
    """Record who did what. Values in `data` must be JSON-serializable."""
    from apps.accounts.models import Device, StaffMember

    if device is None and request is not None:
        session = getattr(request, "auth", None)
        device = getattr(session, "device", None)
    AuditEvent.objects.create(
        business=business,
        actor=actor if isinstance(actor, StaffMember) else None,
        actor_label=str(getattr(actor, "full_name", "") or "")[:120],
        device=device if isinstance(device, Device) else None,
        action=action,
        target_type=target.__class__.__name__ if target is not None else "",
        target_id=str(getattr(target, "pk", "") or "") if target is not None else "",
        data=data,
        ip=client_ip(request),
    )

from __future__ import annotations

from rest_framework.permissions import BasePermission

from .authentication import DevicePrincipal, FirebaseIdentity
from .models import StaffMember


class IsStaff(BasePermission):
    def has_permission(self, request, view):
        return isinstance(request.user, StaffMember) and request.user.is_active


class IsPairedDevice(BasePermission):
    def has_permission(self, request, view):
        return isinstance(request.user, DevicePrincipal)


class IsFirebaseIdentity(BasePermission):
    def has_permission(self, request, view):
        return isinstance(request.user, FirebaseIdentity)


class ActionPermission(IsStaff):
    """Reads `view.permission_map` ({action: code or None}); `"*"` is the default.

    A code of None means any signed-in staff member.
    """

    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        mapping = getattr(view, "permission_map", {}) or {}
        action = getattr(view, "action", None) or request.method.lower()
        code = mapping.get(action, mapping.get("*"))
        if code is None:
            return True
        codes = code if isinstance(code, (list, tuple)) else [code]
        return any(request.user.has_perm_code(c) for c in codes)


def require(*codes: str):
    """Permission class requiring any of `codes`."""

    class _Require(IsStaff):
        def has_permission(self, request, view):
            return super().has_permission(request, view) and any(request.user.has_perm_code(c) for c in codes)

    _Require.__name__ = f"Require_{'_'.join(codes)}"
    return _Require

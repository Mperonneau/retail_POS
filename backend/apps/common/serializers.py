from __future__ import annotations

from rest_framework import serializers


class TenantPrimaryKeyRelatedField(serializers.PrimaryKeyRelatedField):
    """Only accepts rows that belong to the caller's business."""

    def get_queryset(self):
        queryset = super().get_queryset()
        business = self.context.get("business")
        if business is None:
            return queryset.none()
        return queryset.filter(business=business)


def tenant_fk(queryset, **kwargs) -> TenantPrimaryKeyRelatedField:
    kwargs.setdefault("required", False)
    kwargs.setdefault("allow_null", True)
    return TenantPrimaryKeyRelatedField(queryset=queryset, **kwargs)

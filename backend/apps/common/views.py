from __future__ import annotations

from rest_framework import viewsets


class TenantScopedMixin:
    """Limits every query to the caller's business and stamps it on create."""

    def get_queryset(self):
        return super().get_queryset().filter(business=self.request.user.business)

    def perform_create(self, serializer):
        serializer.save(business=self.request.user.business)

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if getattr(self.request, "user", None) is not None:
            context["business"] = getattr(self.request.user, "business", None)
        return context


class TenantModelViewSet(TenantScopedMixin, viewsets.ModelViewSet):
    pass


class TenantReadOnlyViewSet(TenantScopedMixin, viewsets.ReadOnlyModelViewSet):
    pass

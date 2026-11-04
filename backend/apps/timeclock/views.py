from __future__ import annotations

from django.utils.dateparse import parse_date, parse_datetime
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.accounts import roles
from apps.accounts.context import current_location
from apps.accounts.models import StaffMember
from apps.common.exceptions import ApiError
from apps.common.views import TenantScopedMixin

from . import services
from .models import TimeclockEntry


class TimeclockEntrySerializer(serializers.ModelSerializer):
    duration_minutes = serializers.IntegerField(read_only=True)

    class Meta:
        model = TimeclockEntry
        fields = ["id", "staff", "staff_name", "role", "location", "clock_in", "clock_out", "original_clock_in",
                  "original_clock_out", "is_manual", "manual_entered_by", "manual_entered_by_name",
                  "duration_minutes", "created_at", "updated_at"]


def _when(raw, label: str):
    if raw in (None, ""):
        return None
    value = parse_datetime(str(raw))
    if value is None:
        raise ApiError(f"Heure de {label} invalide.")
    return value


class TimeclockViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Everyone punches their own shift; settings access sees and edits all."""

    queryset = TimeclockEntry.objects.all()
    serializer_class = TimeclockEntrySerializer
    filterset_fields = ["staff", "is_manual"]

    def _manager(self) -> bool:
        return self.request.user.has_perm_code(roles.SETTINGS_ACCESS)

    def get_queryset(self):
        qs = super().get_queryset()
        if not self._manager():
            qs = qs.filter(staff=self.request.user)
        params = self.request.query_params
        if params.get("from"):
            qs = qs.filter(clock_in__date__gte=parse_date(params["from"]))
        if params.get("to"):
            qs = qs.filter(clock_in__date__lte=parse_date(params["to"]))
        if params.get("open") in ("1", "true"):
            qs = qs.filter(clock_out__isnull=True)
        return qs

    def _target(self) -> StaffMember:
        staff_id = self.request.data.get("staff")
        if not staff_id or str(staff_id) == str(self.request.user.pk):
            return self.request.user
        if not self._manager():
            raise ApiError("Vous ne pouvez pointer que pour vous-même.", 403)
        staff = StaffMember.objects.filter(business=self.request.user.business, pk=staff_id).first()
        if staff is None:
            raise ApiError("Employé introuvable.", 404)
        return staff

    @action(detail=False, methods=["get"])
    def current(self, request):
        entry = services.open_entry(request.user)
        return Response({"entry": TimeclockEntrySerializer(entry).data if entry else None})

    @action(detail=False, methods=["post"], url_path="clock-in")
    def clock_in(self, request):
        entry = services.clock_in(self._target(), location=current_location(request))
        return Response(TimeclockEntrySerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=["post"], url_path="clock-out")
    def clock_out(self, request):
        return Response(TimeclockEntrySerializer(services.clock_out(self._target())).data)

    @action(detail=False, methods=["post"])
    def manual(self, request):
        if not self._manager():
            raise ApiError("Seul un administrateur peut ajouter un quart.", 403)
        entry = services.add_manual(request.user, self._target(),
                                    clock_in=_when(request.data.get("clock_in"), "arrivée"),
                                    clock_out=_when(request.data.get("clock_out"), "départ"))
        return Response(TimeclockEntrySerializer(entry).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        if not self._manager():
            raise ApiError("Seul un administrateur peut modifier un pointage.", 403)
        entry = services.edit_entry(request.user, self.get_object(),
                                    clock_in=_when(request.data.get("clock_in"), "arrivée"),
                                    clock_out=_when(request.data.get("clock_out"), "départ"))
        return Response(TimeclockEntrySerializer(entry).data)

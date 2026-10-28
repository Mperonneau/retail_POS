from __future__ import annotations

from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.accounts import roles
from apps.accounts.context import current_location
from apps.accounts.models import StaffMember
from apps.accounts.permissions import require
from apps.common.idempotency import idempotent
from apps.common.views import TenantScopedMixin

from . import services
from .models import CashMovement, CashSession
from .serializers import CashMovementSerializer, CashSessionSerializer, ShiftHandoffSerializer


def _session_detail(session: CashSession) -> dict:
    data = CashSessionSerializer(session).data
    if session.status == CashSession.OPEN:
        totals = services.drawer_totals(session)
        data.update({
            "drawer_in_htg": totals.in_htg,
            "drawer_in_usd": totals.in_usd,
            "drawer_out_htg": totals.out_htg,
            "drawer_out_usd": totals.out_usd,
            "drawer_expected_htg": totals.expected_htg,
            "drawer_expected_usd": totals.expected_usd,
        })
    data["tenders"] = services.tender_breakdown(session)
    return data


class CashSessionViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = CashSession.objects.select_related("location")
    serializer_class = CashSessionSerializer
    permission_classes = [require(roles.FINANCIAL_CASH)]
    filterset_fields = ["status", "location"]

    def retrieve(self, request, *args, **kwargs):
        return Response(_session_detail(self.get_object()))

    @action(detail=False, methods=["get"])
    def current(self, request):
        location = current_location(request, request.query_params.get("location"))
        session = services.open_session_for(location)
        return Response({"session": _session_detail(session) if session else None,
                         "location": str(location.pk) if location else None})

    @action(detail=False, methods=["post"])
    @idempotent
    def open(self, request):
        session = services.open_session(
            request.user,
            location=current_location(request, request.data.get("location")),
            opening_htg=request.data.get("opening_htg") or 0,
            opening_usd=request.data.get("opening_usd") or 0,
        )
        return Response(_session_detail(session), status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get", "post"])
    def movements(self, request, pk=None):
        session = self.get_object()
        if request.method == "GET":
            rows = session.movements.all()
            page = self.paginate_queryset(rows)
            return self.get_paginated_response(CashMovementSerializer(page, many=True).data)
        return self._create_movement(request, session)

    @idempotent
    def _create_movement(self, request, session):
        data = request.data
        movement = services.add_movement(
            request.user,
            session,
            type=str(data.get("type") or ""),
            tender=str(data.get("tender") or CashMovement.CASH_HTG),
            amount_htg=data.get("amount_htg") or 0,
            amount_usd=data.get("amount_usd") or 0,
            tips_htg=data.get("tips_htg") or 0,
            tips_usd=data.get("tips_usd") or 0,
            description=str(data.get("description") or ""),
            reference=str(data.get("reference") or ""),
        )
        return Response(CashMovementSerializer(movement).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get", "post"])
    def handoffs(self, request, pk=None):
        session = self.get_object()
        if request.method == "GET":
            return Response(ShiftHandoffSerializer(session.handoffs.all(), many=True).data)
        received = None
        if request.data.get("received_by"):
            received = StaffMember.objects.filter(business=request.user.business, pk=request.data["received_by"]).first()
        record = services.handoff(
            request.user,
            session,
            received_by=received,
            received_by_name=str(request.data.get("received_by_name") or ""),
            counted_htg=request.data.get("counted_htg") or 0,
            counted_usd=request.data.get("counted_usd") or 0,
            note=str(request.data.get("note") or ""),
        )
        return Response(ShiftHandoffSerializer(record).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def close(self, request, pk=None):
        session = services.close_session(
            request.user,
            self.get_object(),
            counted_htg=request.data.get("counted_htg"),
            counted_usd=request.data.get("counted_usd"),
            note=str(request.data.get("note") or ""),
        )
        return Response(_session_detail(session))

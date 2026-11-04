from __future__ import annotations

from datetime import timedelta

from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts import roles
from apps.accounts.models import Location
from apps.accounts.permissions import require
from apps.common.exceptions import ApiError

from . import services

MAX_RANGE_DAYS = 400


def _range(request):
    today = timezone.localdate()
    start = parse_date(request.query_params.get("from") or "") or today.replace(day=1)
    end = parse_date(request.query_params.get("to") or "") or today
    if start > end:
        raise ApiError("La date de début doit précéder la date de fin.")
    if (end - start) > timedelta(days=MAX_RANGE_DAYS):
        raise ApiError("La période est trop longue (13 mois maximum).")
    return start, end


def _location(request):
    raw = request.query_params.get("location")
    if not raw:
        return None
    location = Location.objects.filter(business=request.user.business, pk=raw).first()
    if location is None:
        raise ApiError("Point de vente introuvable.", 404)
    return location


class ReportView(APIView):
    permission_classes = [require(roles.REPORTS_VIEW)]


class SummaryView(ReportView):
    def get(self, request):
        return Response(services.summary(request.user.business, *_range(request), location=_location(request)))


class SalesByDayView(ReportView):
    def get(self, request):
        return Response({"days": services.sales_by_day(request.user.business, *_range(request), location=_location(request))})


class PaymentMethodsView(ReportView):
    def get(self, request):
        return Response({"methods": services.payment_methods(request.user.business, *_range(request),
                                                             location=_location(request))})


class CashiersView(ReportView):
    def get(self, request):
        return Response({"cashiers": services.cashiers(request.user.business, *_range(request), location=_location(request))})


class TopProductsView(ReportView):
    def get(self, request):
        try:
            limit = max(1, min(int(request.query_params.get("limit") or 20), 100))
        except ValueError:
            limit = 20
        return Response({"products": services.top_products(request.user.business, *_range(request), limit=limit,
                                                           location=_location(request))})


class StockValueView(ReportView):
    def get(self, request):
        return Response(services.stock_value(request.user.business))


class ReceivablesView(ReportView):
    def get(self, request):
        return Response(services.receivables(request.user.business))


class CashVariancesView(ReportView):
    def get(self, request):
        return Response({"sessions": services.cash_variances(request.user.business, *_range(request))})


class DashboardView(APIView):
    def get(self, request):
        return Response(services.dashboard(request.user.business, location=_location(request)))

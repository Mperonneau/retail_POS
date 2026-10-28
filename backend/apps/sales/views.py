from __future__ import annotations

from django.db.models import Count, Q
from django.http import HttpResponse
from django.utils.dateparse import parse_date
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.accounts import roles
from apps.accounts.context import current_device, current_location
from apps.accounts.permissions import ActionPermission
from apps.common.exceptions import ApiError
from apps.common.idempotency import idempotent
from apps.common.images import read_private_image
from apps.common.views import TenantScopedMixin
from apps.payments.models import CheckPayment

from . import services
from .models import Order, Quote, QuoteStatus
from .serializers import CheckDetailsSerializer, OrderListSerializer, OrderSerializer, QuoteSerializer, RefundSerializer


def _bool(value) -> bool:
    return str(value).lower() in ("1", "true", "yes", "on")


class OrderViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = Order.objects.all()
    permission_classes = [ActionPermission]
    permission_map = {
        "list": None,
        "retrieve": None,
        "create": roles.TRANSACTIONS_OPERATE,
        "set_status": roles.TRANSACTIONS_OPERATE,
        "collect": roles.TRANSACTIONS_OPERATE,
        "refund": roles.FINANCIAL_CASH,
        "cancel": roles.FINANCIAL_CASH,
        "*": roles.TRANSACTIONS_OPERATE,
    }
    filterset_fields = ["status", "fulfillment_mode", "source", "customer", "location"]
    search_fields = ["number", "client_name", "client_phone"]

    def get_queryset(self):
        qs = super().get_queryset()
        params = self.request.query_params
        if self.action == "list":
            qs = qs.annotate(item_count=Count("lines"))
            if params.get("from"):
                qs = qs.filter(created_at__date__gte=parse_date(params["from"]))
            if params.get("to"):
                qs = qs.filter(created_at__date__lte=parse_date(params["to"]))
            if params.get("q"):
                term = params["q"].strip()
                qs = qs.filter(Q(number__icontains=term) | Q(client_name__icontains=term) |
                               Q(client_phone__icontains=term))
            if _bool(params.get("open")):
                qs = qs.filter(status__in=["paid", "ready", "partiallyPaid", "checkPending"])
            if params.get("since"):
                from django.utils.dateparse import parse_datetime

                since = parse_datetime(params["since"])
                if since:
                    qs = qs.filter(updated_at__gt=since)
        else:
            qs = qs.prefetch_related("lines", "payments__check_details", "status_events", "refunds__lines")
        return qs

    def get_serializer_class(self):
        return OrderListSerializer if self.action == "list" else OrderSerializer

    def _detail(self, order: Order, code=status.HTTP_200_OK) -> Response:
        order = self.get_queryset().model.objects.prefetch_related(
            "lines", "payments__check_details", "status_events", "refunds__lines").get(pk=order.pk)
        return Response(OrderSerializer(order).data, status=code)

    @idempotent
    def create(self, request):
        order, created = services.create_sale(
            request.user, request.data,
            location=current_location(request, request.data.get("location")),
            device=current_device(request),
        )
        return self._detail(order, status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    @action(detail=True, methods=["post"], url_path="status")
    def set_status(self, request, pk=None):
        order = services.set_status(request.user, self.get_object(), str(request.data.get("status") or ""),
                                    str(request.data.get("note") or ""))
        return self._detail(order)

    @action(detail=True, methods=["post"])
    @idempotent
    def collect(self, request, pk=None):
        order = services.collect_payment(request.user, self.get_object(), request.data.get("payments"),
                                         location=current_location(request, request.data.get("location")))
        return self._detail(order)

    @action(detail=True, methods=["post"])
    @idempotent
    def refund(self, request, pk=None):
        record = services.refund(
            request.user, self.get_object(),
            lines=request.data.get("lines"),
            method=str(request.data.get("method") or ""),
            reason=str(request.data.get("reason") or ""),
            restock=_bool(request.data.get("restock", True)),
            amount_htg=request.data.get("amount_htg"),
            location=current_location(request, request.data.get("location")),
        )
        return Response(RefundSerializer(record).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        order = services.cancel(request.user, self.get_object(), reason=str(request.data.get("reason") or ""),
                                restock=_bool(request.data.get("restock", True)))
        return self._detail(order)


class CheckViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = CheckPayment.objects.select_related("payment__order")
    serializer_class = CheckDetailsSerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": roles.TRANSACTIONS_OPERATE, "retrieve": roles.TRANSACTIONS_OPERATE,
                      "image": roles.TRANSACTIONS_OPERATE, "*": roles.FINANCIAL_CASH}
    filterset_fields = ["status"]

    def list(self, request, *args, **kwargs):
        page = self.paginate_queryset(self.filter_queryset(self.get_queryset()))
        rows = []
        for check in page:
            data = CheckDetailsSerializer(check).data
            data.update({"order": str(check.payment.order_id), "order_number": check.payment.order.number})
            rows.append(data)
        return self.get_paginated_response(rows)

    @action(detail=True, methods=["get"])
    def image(self, request, pk=None):
        check = self.get_object()
        if not check.image:
            raise ApiError("Aucune photo pour ce chèque.", 404)
        content, mime = read_private_image(check.image)
        response = HttpResponse(content, content_type=mime)
        response["Cache-Control"] = "private, max-age=300"
        return response

    @action(detail=True, methods=["post"])
    def clear(self, request, pk=None):
        return Response(CheckDetailsSerializer(services.clear_check(request.user, self.get_object())).data)

    @action(detail=True, methods=["post"])
    def refuse(self, request, pk=None):
        check = services.refuse_check(request.user, self.get_object(), reason=str(request.data.get("reason") or ""),
                                      charge_customer=_bool(request.data.get("charge_customer", True)))
        return Response(CheckDetailsSerializer(check).data)


class QuoteViewSet(TenantScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = Quote.objects.prefetch_related("lines")
    serializer_class = QuoteSerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": None, "retrieve": None, "*": roles.TRANSACTIONS_OPERATE}
    filterset_fields = ["status", "customer", "source"]

    @idempotent
    def create(self, request):
        quote = services.save_quote(request.user, request.data,
                                    location=current_location(request, request.data.get("location")))
        return Response(QuoteSerializer(quote).data, status=status.HTTP_201_CREATED)

    def update(self, request, pk=None):
        quote = services.save_quote(request.user, request.data, quote=self.get_object())
        return Response(QuoteSerializer(quote).data)

    def partial_update(self, request, pk=None):
        return self.update(request, pk)

    @action(detail=True, methods=["post"])
    @idempotent
    def convert(self, request, pk=None):
        order = services.convert_quote(request.user, self.get_object(), request.data,
                                       location=current_location(request, request.data.get("location")),
                                       device=current_device(request))
        return Response(OrderSerializer(order).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        quote = self.get_object()
        if quote.status != QuoteStatus.DRAFT:
            raise ApiError("Ce devis a déjà été traité.", 409)
        quote.status = QuoteStatus.CANCELLED
        quote.save(update_fields=["status", "updated_at"])
        return Response(QuoteSerializer(quote).data)

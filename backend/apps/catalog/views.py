from __future__ import annotations

from django.db.models import F, Prefetch
from django.utils.dateparse import parse_datetime
from django_filters import rest_framework as filters
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.accounts import roles
from apps.accounts.permissions import ActionPermission
from apps.common.exceptions import ApiError
from apps.common.money import money
from apps.common.views import TenantModelViewSet, TenantReadOnlyViewSet

from . import services
from .models import Category, Product, ProductOptionChoice, ProductOptionGroup, PurchaseOrder, StockMovement, Supplier
from .serializers import (
    CategorySerializer,
    ProductListSerializer,
    ProductSerializer,
    PurchaseOrderSerializer,
    StockMovementSerializer,
    SupplierSerializer,
)

READ = None
WRITE = roles.CATALOG_MANAGE


class ProductFilter(filters.FilterSet):
    low_stock = filters.BooleanFilter(method="filter_low_stock")
    updated_since = filters.IsoDateTimeFilter(field_name="updated_at", lookup_expr="gt")

    class Meta:
        model = Product
        fields = ["category", "is_active", "show_on_storefront", "sale_mode", "supplier", "barcode"]

    def filter_low_stock(self, queryset, name, value):
        if value:
            return queryset.filter(track_stock=True, stock_quantity__lte=F("min_stock"))
        return queryset


class UpsertMixin:
    """POST with an existing client id updates instead of failing (offline retries)."""

    def create(self, request, *args, **kwargs):
        raw_id = request.data.get("id") if isinstance(request.data, dict) else None
        if raw_id:
            existing = self.get_queryset().filter(pk=raw_id).first()
            if existing is not None:
                serializer = self.get_serializer(existing, data=request.data, partial=True)
                serializer.is_valid(raise_exception=True)
                self.perform_update(serializer)
                return Response(serializer.data)
        return super().create(request, *args, **kwargs)


class CategoryViewSet(TenantModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": READ, "retrieve": READ, "*": WRITE}
    pagination_class = None


class ProductViewSet(UpsertMixin, TenantModelViewSet):
    queryset = Product.objects.select_related("category")
    permission_classes = [ActionPermission]
    permission_map = {"list": READ, "retrieve": READ, "lookup": READ, "movements": READ, "*": WRITE}
    filterset_class = ProductFilter
    search_fields = ["name", "barcode", "sku", "category__name"]
    ordering_fields = ["name", "price_htg", "stock_quantity", "updated_at"]

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action != "list" or self.request.query_params.get("full") == "1":
            queryset = queryset.prefetch_related(
                Prefetch(
                    "option_groups",
                    queryset=ProductOptionGroup.objects.prefetch_related(
                        Prefetch("choices", queryset=ProductOptionChoice.objects.order_by("sort_order", "created_at"))
                    ),
                )
            )
        return queryset

    def get_serializer_class(self):
        if self.action == "list" and self.request.query_params.get("full") != "1":
            return ProductListSerializer
        return ProductSerializer

    def perform_create(self, serializer):
        product = serializer.save(business=self.request.user.business)
        services.record_initial_stock(product, self.request.user)

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.show_on_storefront = False
        instance.save(update_fields=["is_active", "show_on_storefront", "updated_at"])

    @action(detail=False, methods=["get"])
    def lookup(self, request):
        code = (request.query_params.get("barcode") or "").strip()
        if not code:
            raise ApiError("Indiquez un code-barres.")
        product = self.get_queryset().filter(barcode=code, is_active=True).first()
        if product is None:
            raise ApiError("Aucun produit avec ce code-barres.", 404)
        return Response(ProductSerializer(product, context=self.get_serializer_context()).data)

    @action(detail=True, methods=["post"])
    def stock(self, request, pk=None):
        product = self.get_object()
        try:
            quantity = int(request.data.get("quantity"))
        except (TypeError, ValueError) as exc:
            raise ApiError("Quantité invalide.") from exc
        supplier = None
        if request.data.get("supplier"):
            supplier = Supplier.objects.filter(business=request.user.business, pk=request.data["supplier"]).first()
        movement = services.manual_stock_change(
            product,
            kind=str(request.data.get("kind") or StockMovement.STOCK_IN),
            quantity=quantity,
            actor=request.user,
            note=str(request.data.get("note") or ""),
            supplier=supplier,
            supplier_name=str(request.data.get("supplier_name") or ""),
            unit_cost=money(request.data["unit_cost_htg"]) if request.data.get("unit_cost_htg") not in (None, "") else None,
            received_at=parse_datetime(str(request.data.get("received_at") or "")),
        )
        return Response(StockMovementSerializer(movement).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get"])
    def movements(self, request, pk=None):
        product = self.get_object()
        rows = StockMovement.objects.filter(business=request.user.business, product=product).select_related(
            "product", "recorded_by"
        )
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(StockMovementSerializer(page, many=True).data)


class SupplierViewSet(UpsertMixin, TenantModelViewSet):
    queryset = Supplier.objects.prefetch_related("contacts")
    serializer_class = SupplierSerializer
    permission_classes = [ActionPermission]
    permission_map = {"list": READ, "retrieve": READ, "*": WRITE}
    filterset_fields = ["is_active"]
    search_fields = ["name", "phone", "email", "location"]

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])


class PurchaseOrderViewSet(TenantModelViewSet):
    queryset = PurchaseOrder.objects.select_related("supplier").prefetch_related("lines")
    serializer_class = PurchaseOrderSerializer
    permission_classes = [ActionPermission]
    permission_map = {"*": WRITE}
    filterset_fields = ["status", "supplier"]
    search_fields = ["number", "supplier__name"]

    def perform_create(self, serializer):
        serializer.save(business=self.request.user.business, created_by=self.request.user)

    def perform_destroy(self, instance):
        if instance.status != PurchaseOrder.DRAFT:
            raise ApiError("Seul un brouillon peut être supprimé.")
        instance.delete()

    @action(detail=True, methods=["post"])
    def send(self, request, pk=None):
        po = services.send_purchase_order(self.get_object(), request.user)
        return Response(self.get_serializer(po).data)

    @action(detail=True, methods=["post"])
    def receive(self, request, pk=None):
        po = services.receive_purchase_order(self.get_object(), request.data.get("lines") or [], request.user)
        return Response(self.get_serializer(self.get_queryset().get(pk=po.pk)).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        po = services.cancel_purchase_order(self.get_object(), request.user)
        return Response(self.get_serializer(po).data)


class StockMovementViewSet(TenantReadOnlyViewSet):
    queryset = StockMovement.objects.select_related("product", "recorded_by")
    serializer_class = StockMovementSerializer
    permission_classes = [ActionPermission]
    permission_map = {"*": READ}
    filterset_fields = ["product", "kind"]

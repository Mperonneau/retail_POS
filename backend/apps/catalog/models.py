from __future__ import annotations

from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import Q
from django.utils import timezone

from apps.common.models import TenantModel, UUIDModel

ZERO = Decimal("0")


def money_field(**kwargs):
    kwargs.setdefault("max_digits", 14)
    kwargs.setdefault("decimal_places", 2)
    kwargs.setdefault("default", ZERO)
    return models.DecimalField(**kwargs)


class Category(TenantModel):
    name = models.CharField(max_length=60)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "name"]
        constraints = [models.UniqueConstraint(fields=["business", "name"], name="uniq_category_name")]

    def __str__(self) -> str:
        return self.name


class Supplier(TenantModel):
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=40, blank=True)
    email = models.EmailField(blank=True)
    location = models.CharField(max_length=160, blank=True)
    note = models.TextField(blank=True, max_length=1000)
    categories = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self) -> str:
        return self.name


class SupplierContact(UUIDModel):
    supplier = models.ForeignKey(Supplier, on_delete=models.CASCADE, related_name="contacts")
    name = models.CharField(max_length=120)
    title = models.CharField(max_length=80, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    email = models.EmailField(blank=True)


class Product(TenantModel):
    PIECE = "piece"
    ROLL = "roll"
    CASE = "case"
    SALE_MODES = [(PIECE, "À la pièce"), (ROLL, "Au pouce / rouleau"), (CASE, "Caisse et unité")]

    # Id the register used before the backend (kept for the vitrine contract).
    external_id = models.CharField(max_length=40, null=True, blank=True)
    name = models.CharField(max_length=120)
    category = models.ForeignKey(Category, null=True, blank=True, on_delete=models.SET_NULL, related_name="products")
    description = models.TextField(blank=True, max_length=600)
    barcode = models.CharField(max_length=64, blank=True)
    sku = models.CharField(max_length=64, blank=True)
    price_htg = money_field()
    price_usd = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    regular_price_htg = money_field()
    cost_htg = money_field()
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    sale_mode = models.CharField(max_length=5, choices=SALE_MODES, default=PIECE)
    roll_price_htg = money_field()
    regular_roll_price_htg = money_field()
    roll_width = models.PositiveIntegerField(default=0)
    min_width = models.PositiveIntegerField(default=0)
    limit_length = models.BooleanField(default=False)
    case_price_htg = money_field()
    regular_case_price_htg = money_field()
    units_per_case = models.PositiveIntegerField(default=0)
    track_stock = models.BooleanField(default=True)
    # Pieces, inches (roll) or single units (case). Can dip below zero when an
    # offline sale syncs after the last unit was already sold.
    stock_quantity = models.IntegerField(default=0)
    min_stock = models.IntegerField(default=0)
    stock_unit = models.CharField(max_length=12, blank=True)
    unit = models.CharField(max_length=12, blank=True)
    photo = models.CharField(max_length=80, blank=True)
    supplier = models.ForeignKey(Supplier, null=True, blank=True, on_delete=models.SET_NULL, related_name="products")
    is_active = models.BooleanField(default=True)
    show_on_storefront = models.BooleanField(default=False)

    class Meta:
        ordering = ["name"]
        indexes = [
            models.Index(fields=["business", "is_active", "name"], name="product_biz_active"),
            models.Index(fields=["business", "barcode"], name="product_biz_barcode"),
            models.Index(fields=["business", "updated_at"], name="product_biz_sync"),
            models.Index(fields=["business", "show_on_storefront"], name="product_biz_vitrine"),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["business", "external_id"], condition=Q(external_id__isnull=False), name="uniq_product_external"
            ),
        ]

    def __str__(self) -> str:
        return self.name

    @property
    def is_low_stock(self) -> bool:
        return self.track_stock and self.stock_quantity <= self.min_stock

    @property
    def public_id(self) -> str:
        return self.external_id or str(self.pk)

    def clean(self) -> None:
        errors = {}
        if self.price_htg is not None and self.price_htg < 0:
            errors["price_htg"] = "Le prix ne peut pas être négatif."
        if self.sale_mode == self.ROLL:
            if self.roll_width < 1:
                errors["roll_width"] = "Indiquez la longueur du rouleau entier (po)."
            if self.min_width < 1:
                errors["min_width"] = "Indiquez la longueur minimum (po)."
            elif self.roll_width and self.min_width > self.roll_width:
                errors["min_width"] = "Le minimum dépasse la longueur du rouleau."
            if self.roll_price_htg <= 0:
                errors["roll_price_htg"] = "Indiquez le prix du rouleau entier."
        if self.sale_mode == self.CASE:
            if self.units_per_case < 2:
                errors["units_per_case"] = "Une caisse contient au moins 2 unités."
            if self.case_price_htg <= 0:
                errors["case_price_htg"] = "Indiquez le prix de la caisse."
        if errors:
            raise ValidationError(errors)


class ProductOptionGroup(UUIDModel):
    KINDS = [("size", "Taille"), ("color", "Couleur"), ("extra", "Supplément"), ("other", "Autre")]

    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="option_groups")
    external_id = models.CharField(max_length=80, blank=True)
    name = models.CharField(max_length=60)
    kind = models.CharField(max_length=6, choices=KINDS, default="other")
    required = models.BooleanField(default=False)
    multiple = models.BooleanField(default=False)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "created_at"]

    @property
    def public_id(self) -> str:
        return self.external_id or str(self.pk)


class ProductOptionChoice(UUIDModel):
    group = models.ForeignKey(ProductOptionGroup, on_delete=models.CASCADE, related_name="choices")
    external_id = models.CharField(max_length=80, blank=True)
    name = models.CharField(max_length=60)
    price_delta_htg = money_field()
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "created_at"]

    @property
    def public_id(self) -> str:
        return self.external_id or str(self.pk)


class PurchaseOrder(TenantModel):
    DRAFT = "draft"
    SENT = "sent"
    PARTIAL = "partially_received"
    RECEIVED = "received"
    CANCELLED = "cancelled"
    STATUSES = [
        (DRAFT, "Brouillon"),
        (SENT, "Envoyé"),
        (PARTIAL, "Partiellement reçu"),
        (RECEIVED, "Entièrement reçu"),
        (CANCELLED, "Annulé"),
    ]

    number = models.CharField(max_length=30)
    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT, related_name="purchase_orders")
    location = models.ForeignKey("accounts.Location", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    status = models.CharField(max_length=20, choices=STATUSES, default=DRAFT)
    expected_at = models.DateField(null=True, blank=True)
    note = models.TextField(blank=True, max_length=1000)
    total_cost_htg = money_field()
    created_by = models.ForeignKey("accounts.StaffMember", null=True, on_delete=models.SET_NULL, related_name="+")
    sent_at = models.DateTimeField(null=True, blank=True)
    received_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "status"], name="po_biz_status")]


class PurchaseOrderLine(UUIDModel):
    purchase_order = models.ForeignKey(PurchaseOrder, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey(Product, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    product_name = models.CharField(max_length=120)
    quantity_ordered = models.PositiveIntegerField()
    quantity_received = models.PositiveIntegerField(default=0)
    unit_cost_htg = money_field()

    @property
    def remaining(self) -> int:
        return max(0, self.quantity_ordered - self.quantity_received)


class StockMovement(TenantModel):
    STOCK_IN = "stockIn"
    SALE = "sale"
    ADJUSTMENT = "adjustment"
    RETURN = "return"
    PO_RECEIPT = "poReceipt"
    RESERVATION = "reservation"
    RELEASE = "release"
    KINDS = [
        (STOCK_IN, "Entrée"),
        (SALE, "Vente"),
        (ADJUSTMENT, "Ajustement"),
        (RETURN, "Retour client"),
        (PO_RECEIPT, "Réception fournisseur"),
        (RESERVATION, "Réservation vitrine"),
        (RELEASE, "Réservation libérée"),
    ]

    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="movements")
    kind = models.CharField(max_length=12, choices=KINDS)
    quantity_delta = models.IntegerField()
    stock_after = models.IntegerField()
    received_at = models.DateTimeField(default=timezone.now)
    supplier = models.ForeignKey(Supplier, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    supplier_name = models.CharField(max_length=120, blank=True)
    purchase_order = models.ForeignKey(PurchaseOrder, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    reference_type = models.CharField(max_length=20, blank=True)
    reference_id = models.CharField(max_length=64, blank=True)
    note = models.CharField(max_length=300, blank=True)
    unit_cost_htg = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    recorded_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "product", "-created_at"], name="stock_biz_product")]

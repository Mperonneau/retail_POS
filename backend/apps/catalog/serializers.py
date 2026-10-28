from __future__ import annotations

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from rest_framework import serializers

from apps.common.images import public_image_url, save_public_image
from apps.common.serializers import tenant_fk

from .models import (
    Category,
    Product,
    ProductOptionChoice,
    ProductOptionGroup,
    PurchaseOrder,
    PurchaseOrderLine,
    StockMovement,
    Supplier,
    SupplierContact,
)

MAX_OPTION_GROUPS = 12
MAX_OPTION_CHOICES = 30


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name", "sort_order", "updated_at"]
        read_only_fields = ["id", "updated_at"]


class OptionChoiceSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)

    class Meta:
        model = ProductOptionChoice
        fields = ["id", "external_id", "name", "price_delta_htg", "sort_order"]


class OptionGroupSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    choices = OptionChoiceSerializer(many=True)

    class Meta:
        model = ProductOptionGroup
        fields = ["id", "external_id", "name", "kind", "required", "multiple", "sort_order", "choices"]

    def validate_choices(self, value):
        if not value:
            raise serializers.ValidationError("Ajoutez au moins un choix.")
        if len(value) > MAX_OPTION_CHOICES:
            raise serializers.ValidationError(f"{MAX_OPTION_CHOICES} choix au maximum.")
        return value


class ProductListSerializer(serializers.ModelSerializer):
    """Lean shape for long lists on slow connections."""

    category_name = serializers.CharField(source="category.name", default="", read_only=True)
    photo_url = serializers.SerializerMethodField()
    is_low_stock = serializers.BooleanField(read_only=True)

    class Meta:
        model = Product
        fields = [
            "id", "external_id", "name", "category", "category_name", "barcode", "price_htg", "price_usd",
            "discount_percent", "sale_mode", "track_stock", "stock_quantity", "min_stock", "is_low_stock",
            "stock_unit", "photo_url", "is_active", "show_on_storefront", "updated_at",
        ]

    def get_photo_url(self, obj) -> str:
        return public_image_url(obj.photo)


class ProductSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    category = tenant_fk(Category.objects.all())
    category_name = serializers.CharField(required=False, allow_blank=True, max_length=60, write_only=True)
    supplier = tenant_fk(Supplier.objects.all())
    option_groups = OptionGroupSerializer(many=True, required=False)
    photo_data_url = serializers.CharField(required=False, allow_blank=True, write_only=True)
    photo_url = serializers.SerializerMethodField()
    is_low_stock = serializers.BooleanField(read_only=True)
    category_label = serializers.CharField(source="category.name", default="", read_only=True)

    class Meta:
        model = Product
        fields = [
            "id", "external_id", "name", "category", "category_name", "category_label", "description", "barcode",
            "sku", "price_htg", "price_usd", "regular_price_htg", "cost_htg", "discount_percent", "sale_mode",
            "roll_price_htg", "regular_roll_price_htg", "roll_width", "min_width", "limit_length",
            "case_price_htg", "regular_case_price_htg", "units_per_case", "track_stock", "stock_quantity",
            "min_stock", "is_low_stock", "stock_unit", "unit", "photo_url", "photo_data_url", "supplier",
            "is_active", "show_on_storefront", "option_groups", "created_at", "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]
        extra_kwargs = {"stock_quantity": {"required": False}}

    def get_photo_url(self, obj) -> str:
        return public_image_url(obj.photo)

    def validate_option_groups(self, value):
        if len(value) > MAX_OPTION_GROUPS:
            raise serializers.ValidationError(f"{MAX_OPTION_GROUPS} groupes d'options au maximum.")
        return value

    def validate(self, attrs):
        if self.instance is not None and "stock_quantity" in attrs:
            # Stock only moves through movements so every change is traceable.
            attrs.pop("stock_quantity")
        business = self.context["business"]
        name = attrs.pop("category_name", None)
        if name is not None and "category" not in attrs:
            name = name.strip()
            attrs["category"] = Category.objects.get_or_create(business=business, name=name)[0] if name else None
        candidate = Product(**{k: v for k, v in attrs.items() if k not in ("option_groups", "photo_data_url")})
        if self.instance is not None:
            for field in Product._meta.concrete_fields:
                if field.name not in attrs and field.name != "id":
                    setattr(candidate, field.attname, getattr(self.instance, field.attname))
        try:
            candidate.clean()
        except DjangoValidationError as exc:
            raise serializers.ValidationError(exc.message_dict) from exc
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        groups = validated_data.pop("option_groups", [])
        photo = validated_data.pop("photo_data_url", "")
        if photo:
            validated_data["photo"] = save_public_image(photo)
        product = Product.objects.create(**validated_data)
        _replace_options(product, groups)
        return product

    @transaction.atomic
    def update(self, instance, validated_data):
        groups = validated_data.pop("option_groups", None)
        photo = validated_data.pop("photo_data_url", None)
        validated_data.pop("id", None)
        if photo is not None:
            validated_data["photo"] = save_public_image(photo) if photo else ""
        for key, value in validated_data.items():
            setattr(instance, key, value)
        instance.save()
        if groups is not None:
            _replace_options(instance, groups)
        return instance


def _replace_options(product: Product, groups: list[dict]) -> None:
    product.option_groups.all().delete()
    for g_index, group in enumerate(groups):
        choices = group.pop("choices", [])
        group.pop("id", None)
        group.setdefault("sort_order", g_index)
        row = ProductOptionGroup.objects.create(product=product, **group)
        ProductOptionChoice.objects.bulk_create(
            [
                ProductOptionChoice(
                    group=row,
                    external_id=c.get("external_id", ""),
                    name=c["name"],
                    price_delta_htg=c.get("price_delta_htg", 0),
                    sort_order=c.get("sort_order", c_index),
                )
                for c_index, c in enumerate(choices)
            ]
        )


class SupplierContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupplierContact
        fields = ["id", "name", "title", "phone", "email"]
        read_only_fields = ["id"]


class SupplierSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    contacts = SupplierContactSerializer(many=True, required=False)

    class Meta:
        model = Supplier
        fields = ["id", "name", "phone", "email", "location", "note", "categories", "is_active", "contacts", "updated_at"]
        read_only_fields = ["updated_at"]

    def validate_categories(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Liste attendue.")
        return [str(v).strip()[:80] for v in value if str(v).strip()][:30]

    @transaction.atomic
    def create(self, validated_data):
        contacts = validated_data.pop("contacts", [])
        supplier = Supplier.objects.create(**validated_data)
        SupplierContact.objects.bulk_create([SupplierContact(supplier=supplier, **c) for c in contacts])
        return supplier

    @transaction.atomic
    def update(self, instance, validated_data):
        contacts = validated_data.pop("contacts", None)
        validated_data.pop("id", None)
        for key, value in validated_data.items():
            setattr(instance, key, value)
        instance.save()
        if contacts is not None:
            instance.contacts.all().delete()
            SupplierContact.objects.bulk_create([SupplierContact(supplier=instance, **c) for c in contacts])
        return instance


class PurchaseOrderLineSerializer(serializers.ModelSerializer):
    product = tenant_fk(Product.objects.all())
    remaining = serializers.IntegerField(read_only=True)

    class Meta:
        model = PurchaseOrderLine
        fields = ["id", "product", "product_name", "quantity_ordered", "quantity_received", "remaining", "unit_cost_htg"]
        read_only_fields = ["id", "quantity_received"]
        extra_kwargs = {"product_name": {"required": False}}

    def validate_quantity_ordered(self, value):
        if value < 1:
            raise serializers.ValidationError("Quantité invalide.")
        return value


class PurchaseOrderSerializer(serializers.ModelSerializer):
    supplier = tenant_fk(Supplier.objects.all(), allow_null=False, required=True)
    supplier_name = serializers.CharField(source="supplier.name", read_only=True)
    lines = PurchaseOrderLineSerializer(many=True)

    class Meta:
        model = PurchaseOrder
        fields = [
            "id", "number", "supplier", "supplier_name", "location", "status", "expected_at", "note",
            "total_cost_htg", "sent_at", "received_at", "lines", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "number", "status", "total_cost_htg", "sent_at", "received_at", "created_at",
                            "updated_at"]

    def validate_lines(self, value):
        if not value:
            raise serializers.ValidationError("Ajoutez au moins un article.")
        for line in value:
            if not line.get("product_name") and line.get("product") is None:
                raise serializers.ValidationError("Chaque ligne doit avoir un produit.")
        return value

    def _write_lines(self, po: PurchaseOrder, lines: list[dict]) -> None:
        po.lines.all().delete()
        rows = []
        total = 0
        for line in lines:
            product = line.get("product")
            name = line.get("product_name") or (product.name if product else "")
            rows.append(PurchaseOrderLine(
                purchase_order=po,
                product=product,
                product_name=name[:120],
                quantity_ordered=line["quantity_ordered"],
                unit_cost_htg=line.get("unit_cost_htg", 0),
            ))
            total += line["quantity_ordered"] * line.get("unit_cost_htg", 0)
        PurchaseOrderLine.objects.bulk_create(rows)
        po.total_cost_htg = total
        po.save(update_fields=["total_cost_htg", "updated_at"])

    @transaction.atomic
    def create(self, validated_data):
        from apps.common.numbering import next_number

        lines = validated_data.pop("lines")
        validated_data["number"] = next_number(validated_data["business"], "BC")
        po = PurchaseOrder.objects.create(**validated_data)
        self._write_lines(po, lines)
        return po

    @transaction.atomic
    def update(self, instance, validated_data):
        if instance.status != PurchaseOrder.DRAFT:
            raise serializers.ValidationError("Seul un bon de commande en brouillon peut être modifié.")
        lines = validated_data.pop("lines", None)
        for key, value in validated_data.items():
            setattr(instance, key, value)
        instance.save()
        if lines is not None:
            self._write_lines(instance, lines)
        return instance


class StockMovementSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source="product.name", read_only=True)
    recorded_by_name = serializers.CharField(source="recorded_by.full_name", default="", read_only=True)

    class Meta:
        model = StockMovement
        fields = [
            "id", "product", "product_name", "kind", "quantity_delta", "stock_after", "received_at", "supplier_name",
            "purchase_order", "reference_type", "reference_id", "note", "unit_cost_htg", "recorded_by_name",
            "created_at",
        ]

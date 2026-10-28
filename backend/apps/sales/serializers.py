from rest_framework import serializers

from apps.payments.models import CheckPayment, Payment

from .models import Order, OrderLine, OrderStatusEvent, Quote, QuoteLine, Refund, RefundLine


class OrderLineSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderLine
        fields = ["id", "product", "product_name", "options_label", "options", "measure", "width", "quantity",
                  "unit_price_htg", "unit_price_usd", "line_total_htg", "stock_units", "refunded_quantity",
                  "price_overridden"]


class CheckDetailsSerializer(serializers.ModelSerializer):
    has_image = serializers.SerializerMethodField()
    clearance_label = serializers.CharField(read_only=True)

    class Meta:
        model = CheckPayment
        fields = ["id", "number", "bank", "payer_name", "check_date", "amount_htg", "status", "clearance_label",
                  "cleared_at", "cleared_by_name", "refused_at", "refused_reason", "has_image", "credit_posted"]

    def get_has_image(self, obj) -> bool:
        return bool(obj.image)


class PaymentSerializer(serializers.ModelSerializer):
    check_details = serializers.SerializerMethodField()

    class Meta:
        model = Payment
        fields = ["id", "method", "status", "amount_htg", "amount_usd", "tendered_htg", "change_htg", "reference",
                  "last_four", "recorded_by_name", "created_at", "check_details"]

    def get_check_details(self, obj):
        details = getattr(obj, "check_details", None) if obj.method == Payment.CHECK else None
        return CheckDetailsSerializer(details).data if details else None


class OrderStatusEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderStatusEvent
        fields = ["from_status", "to_status", "actor_name", "note", "created_at"]


class RefundLineSerializer(serializers.ModelSerializer):
    class Meta:
        model = RefundLine
        fields = ["order_line", "quantity", "amount_htg"]


class RefundSerializer(serializers.ModelSerializer):
    lines = RefundLineSerializer(many=True, read_only=True)

    class Meta:
        model = Refund
        fields = ["id", "number", "order", "amount_htg", "method", "reason", "restock", "recorded_by_name",
                  "created_at", "lines"]


ORDER_FIELDS = [
    "id", "number", "source", "status", "location", "customer", "client_name", "client_phone", "client_email",
    "fulfillment_mode", "delivery_location", "delivery_phone", "delivery_fee_htg", "discount_percent",
    "tax_percent", "service_charge_percent", "subtotal_htg", "discount_htg", "tax_htg", "service_charge_htg",
    "total_htg", "amount_paid_htg", "balance_due_htg", "refunded_htg", "usd_rate", "payment_method",
    "payment_last_four", "recorded_by_name", "note", "paid_at", "completed_at", "cancelled_at", "cancel_reason",
    "client_created_at", "created_at", "updated_at",
]


class OrderListSerializer(serializers.ModelSerializer):
    item_count = serializers.IntegerField(read_only=True, default=None)

    class Meta:
        model = Order
        fields = ORDER_FIELDS + ["item_count"]


class OrderSerializer(serializers.ModelSerializer):
    lines = OrderLineSerializer(many=True, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    status_events = OrderStatusEventSerializer(many=True, read_only=True)
    refunds = RefundSerializer(many=True, read_only=True)
    total_usd = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = ORDER_FIELDS + ["from_quote", "total_usd", "lines", "payments", "status_events", "refunds"]

    def get_total_usd(self, obj):
        return round(float(obj.total_htg / obj.usd_rate), 2) if obj.usd_rate else None


class QuoteLineSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuoteLine
        fields = ["id", "product", "product_name", "options_label", "choices", "measure", "width", "quantity",
                  "unit_price_htg", "line_total_htg"]


class QuoteSerializer(serializers.ModelSerializer):
    lines = QuoteLineSerializer(many=True, read_only=True)

    class Meta:
        model = Quote
        fields = ["id", "number", "status", "source", "location", "customer", "client_name", "client_phone",
                  "client_email", "fulfillment_mode", "delivery_location", "delivery_phone", "delivery_fee_htg",
                  "discount_percent", "subtotal_htg", "total_htg", "note", "valid_until", "payment_link_sent",
                  "created_by_name", "converted_order", "created_at", "updated_at", "lines"]

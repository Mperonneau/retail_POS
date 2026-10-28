from rest_framework import serializers

from .models import PayLink


class PayLinkSerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source="order.number", read_only=True, default=None)

    class Meta:
        model = PayLink
        fields = ["id", "reference", "customer", "customer_name", "customer_phone", "payer_email", "amount_htg",
                  "usd_rate", "order_usd_cents", "status", "channel", "source", "sent_to", "order", "order_number",
                  "note", "expires_at", "paid_at", "canceled_at", "canceled_by", "created_by_name", "payment_url",
                  "payer_total_usd_cents", "platform_fee_usd_cents", "stripe_fee_usd_cents",
                  "payment_transaction_id", "payment_last4", "payment_method", "created_at", "updated_at"]
        read_only_fields = fields

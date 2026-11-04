from rest_framework import serializers

from .models import Customer, CustomerNote, CustomerTransaction, PaymentSchedule, StoreCreditEntry


class CustomerListSerializer(serializers.ModelSerializer):
    class Meta:
        model = Customer
        fields = [
            "id", "name", "phone", "email", "balance_htg", "store_credit_htg", "credit_limit_htg",
            "is_credit_blocked", "is_active", "total_spent_htg", "last_purchase_at", "updated_at",
        ]


class CustomerSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    has_store_credit_identity = serializers.BooleanField(read_only=True)
    is_over_limit = serializers.BooleanField(read_only=True)

    class Meta:
        model = Customer
        fields = [
            "id", "external_id", "name", "first_name", "last_name", "phone", "secondary_phone", "email", "address",
            "notes", "date_of_birth", "government_id", "credit_limit_htg", "credit_limit_usd", "is_credit_blocked",
            "blocked_reason", "blocked_by", "blocked_at", "is_active", "balance_htg", "store_credit_htg",
            "total_spent_htg", "total_purchases", "last_purchase_at", "has_store_credit_identity", "is_over_limit",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "is_credit_blocked", "blocked_reason", "blocked_by", "blocked_at", "balance_htg", "store_credit_htg",
            "total_spent_htg", "total_purchases", "last_purchase_at", "created_at", "updated_at",
        ]

    def validate(self, attrs):
        name = attrs.get("name", getattr(self.instance, "name", "")) or ""
        first = attrs.get("first_name", getattr(self.instance, "first_name", "")) or ""
        last = attrs.get("last_name", getattr(self.instance, "last_name", "")) or ""
        if not name.strip() and not f"{first} {last}".strip():
            raise serializers.ValidationError("Indiquez le nom du client.")
        for key in ("credit_limit_htg", "credit_limit_usd"):
            value = attrs.get(key)
            if value is not None and value < 0:
                raise serializers.ValidationError({key: "La limite ne peut pas être négative."})
        return attrs


class CustomerTransactionSerializer(serializers.ModelSerializer):
    credited_htg = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)

    class Meta:
        model = CustomerTransaction
        fields = [
            "id", "customer", "kind", "amount_htg", "amount_usd", "paid_amount_htg", "credited_htg",
            "balance_after_htg", "order", "description", "payment_method", "receipt_number", "recorded_by_name",
            "receipt_sent", "created_at",
        ]


class StoreCreditEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = StoreCreditEntry
        fields = ["id", "customer", "kind", "amount_htg", "balance_after_htg", "description", "order", "paylink",
                  "recorded_by_name", "created_at"]


class CustomerNoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = CustomerNote
        fields = ["id", "customer", "text", "created_by_name", "created_at"]
        read_only_fields = ["id", "customer", "created_by_name", "created_at"]


class PaymentScheduleSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentSchedule
        fields = ["id", "customer", "scheduled_date", "amount_htg", "is_paid", "paid_at", "note"]
        read_only_fields = ["id", "customer", "is_paid", "paid_at"]

    def validate_amount_htg(self, value):
        if value <= 0:
            raise serializers.ValidationError("Le montant doit être supérieur à zéro.")
        return value

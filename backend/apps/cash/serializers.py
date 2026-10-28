from rest_framework import serializers

from .models import CashMovement, CashSession, ShiftHandoff


class CashMovementSerializer(serializers.ModelSerializer):
    class Meta:
        model = CashMovement
        fields = [
            "id", "session", "type", "tender", "amount_htg", "amount_usd", "tips_htg", "tips_usd", "description",
            "order", "reference", "recorded_by_name", "created_at",
        ]
        read_only_fields = fields


class ShiftHandoffSerializer(serializers.ModelSerializer):
    delta_htg = serializers.SerializerMethodField()
    delta_usd = serializers.SerializerMethodField()

    class Meta:
        model = ShiftHandoff
        fields = [
            "id", "session", "closed_by_name", "received_by_name", "opening_htg", "opening_usd", "inflow_htg",
            "inflow_usd", "outflow_htg", "outflow_usd", "expected_htg", "expected_usd", "counted_htg", "counted_usd",
            "delta_htg", "delta_usd", "note", "created_at",
        ]
        read_only_fields = fields

    def get_delta_htg(self, obj):
        return obj.counted_htg - obj.expected_htg

    def get_delta_usd(self, obj):
        return obj.counted_usd - obj.expected_usd


class CashSessionSerializer(serializers.ModelSerializer):
    location_name = serializers.CharField(source="location.name", read_only=True)
    is_balanced = serializers.SerializerMethodField()

    class Meta:
        model = CashSession
        fields = [
            "id", "location", "location_name", "status", "opened_by_name", "opened_at", "opening_htg", "opening_usd",
            "closed_at", "closed_by_name", "closing_note", "total_in_htg", "total_in_usd", "total_out_htg",
            "total_out_usd", "expected_htg", "expected_usd", "counted_htg", "counted_usd", "over_short_htg",
            "over_short_usd", "is_balanced", "updated_at",
        ]
        read_only_fields = fields

    def get_is_balanced(self, obj) -> bool | None:
        if obj.status != CashSession.CLOSED:
            return None
        return abs(obj.over_short_htg) < 1 and abs(obj.over_short_usd) < 0.01

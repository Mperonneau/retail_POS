from __future__ import annotations

from django.db.models import Count, Q, Sum
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.accounts import roles
from apps.accounts.context import current_location
from apps.accounts.permissions import ActionPermission
from apps.catalog.views import UpsertMixin
from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.idempotency import idempotent
from apps.common.views import TenantModelViewSet

from . import ledger
from .models import Customer, CustomerNote, CustomerTransaction, PaymentSchedule, StoreCreditEntry
from .serializers import (
    CustomerListSerializer,
    CustomerNoteSerializer,
    CustomerSerializer,
    CustomerTransactionSerializer,
    PaymentScheduleSerializer,
    StoreCreditEntrySerializer,
)


class CustomerViewSet(UpsertMixin, TenantModelViewSet):
    queryset = Customer.objects.all()
    permission_classes = [ActionPermission]
    permission_map = {
        "charge": roles.CLIENT_CREDIT_GRANT,
        "block": roles.CLIENT_CREDIT_GRANT,
        "unblock": roles.CLIENT_CREDIT_GRANT,
        "adjustment": roles.FINANCIAL_CASH,
        "issue_store_credit": roles.FINANCIAL_CASH,
        "payment": [roles.TRANSACTIONS_OPERATE, roles.FINANCIAL_CASH],
        "destroy": roles.SETTINGS_ACCESS,
        "*": roles.TRANSACTIONS_OPERATE,
    }
    filterset_fields = ["is_active", "is_credit_blocked"]
    search_fields = ["name", "phone", "phone_digits", "email", "government_id"]
    ordering_fields = ["name", "balance_htg", "last_purchase_at", "created_at"]

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.request.query_params.get("has_balance") == "1":
            queryset = queryset.filter(balance_htg__gt=0)
        if self.request.query_params.get("has_store_credit") == "1":
            queryset = queryset.filter(store_credit_htg__gt=0)
        return queryset

    def get_serializer_class(self):
        return CustomerListSerializer if self.action == "list" else CustomerSerializer

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    def _amount(self, request):
        return request.data.get("amount_htg")

    @action(detail=True, methods=["post"])
    @idempotent
    def charge(self, request, pk=None):
        entry = ledger.post_charge(
            self.get_object(), self._amount(request), actor=request.user,
            description=str(request.data.get("description") or "Vente à crédit"),
            paid_amount_htg=request.data.get("paid_amount_htg") or 0,
        )
        return Response(CustomerTransactionSerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    @idempotent
    def payment(self, request, pk=None):
        customer = self.get_object()
        method = str(request.data.get("method") or "cash")
        entry = ledger.post_payment(
            customer, self._amount(request), actor=request.user, method=method,
            description=str(request.data.get("description") or "Paiement reçu"),
        )
        from apps.cash.services import record_customer_payment

        record_customer_payment(request.user, entry, method, request.data.get("amount_usd"),
                                location=current_location(request, request.data.get("location")))
        schedule_id = request.data.get("schedule")
        if schedule_id:
            PaymentSchedule.objects.filter(business=customer.business, customer=customer, pk=schedule_id).update(
                is_paid=True, paid_at=timezone.now()
            )
        return Response(CustomerTransactionSerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    @idempotent
    def adjustment(self, request, pk=None):
        entry = ledger.post_adjustment(
            self.get_object(), self._amount(request), actor=request.user,
            description=str(request.data.get("description") or ""),
        )
        return Response(CustomerTransactionSerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="store-credit/issue")
    @idempotent
    def issue_store_credit(self, request, pk=None):
        entry = ledger.issue_store_credit(
            self.get_object(), self._amount(request), actor=request.user,
            description=str(request.data.get("description") or "Avoir commercial"),
        )
        return Response(StoreCreditEntrySerializer(entry).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def block(self, request, pk=None):
        customer = self.get_object()
        reason = str(request.data.get("reason") or "").strip()
        if not reason:
            raise ApiError("Indiquez la raison du blocage.")
        customer.is_credit_blocked = True
        customer.blocked_reason = reason[:200]
        customer.blocked_by = request.user.full_name
        customer.blocked_at = timezone.now()
        customer.save(update_fields=["is_credit_blocked", "blocked_reason", "blocked_by", "blocked_at", "updated_at"])
        audit(customer.business, "customer.blocked", actor=request.user, target=customer, reason=reason)
        return Response(CustomerSerializer(customer).data)

    @action(detail=True, methods=["post"])
    def unblock(self, request, pk=None):
        customer = self.get_object()
        customer.is_credit_blocked = False
        customer.blocked_reason = ""
        customer.blocked_by = ""
        customer.blocked_at = None
        customer.save(update_fields=["is_credit_blocked", "blocked_reason", "blocked_by", "blocked_at", "updated_at"])
        audit(customer.business, "customer.unblocked", actor=request.user, target=customer)
        return Response(CustomerSerializer(customer).data)

    @action(detail=True, methods=["get"])
    def transactions(self, request, pk=None):
        rows = CustomerTransaction.objects.filter(business=request.user.business, customer_id=pk)
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(CustomerTransactionSerializer(page, many=True).data)

    @action(detail=True, methods=["get"], url_path="store-credit")
    def store_credit(self, request, pk=None):
        rows = StoreCreditEntry.objects.filter(business=request.user.business, customer_id=pk)
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(StoreCreditEntrySerializer(page, many=True).data)

    @action(detail=True, methods=["get", "post"])
    def notes(self, request, pk=None):
        customer = self.get_object()
        if request.method == "GET":
            rows = CustomerNote.objects.filter(business=customer.business, customer=customer)
            return Response(CustomerNoteSerializer(rows, many=True).data)
        text = str(request.data.get("text") or "").strip()
        if not text:
            raise ApiError("La note est vide.")
        note = CustomerNote.objects.create(
            business=customer.business, customer=customer, text=text[:1000],
            created_by=request.user, created_by_name=request.user.full_name,
        )
        return Response(CustomerNoteSerializer(note).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get", "post"])
    def schedules(self, request, pk=None):
        customer = self.get_object()
        if request.method == "GET":
            rows = PaymentSchedule.objects.filter(business=customer.business, customer=customer)
            return Response(PaymentScheduleSerializer(rows, many=True).data)
        serializer = PaymentScheduleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(business=customer.business, customer=customer)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get"])
    def statement(self, request, pk=None):
        """Account statement for a period: opening balance, entries, closing balance."""
        customer = self.get_object()
        start = parse_date(request.query_params.get("from") or "")
        end = parse_date(request.query_params.get("to") or "")
        rows = CustomerTransaction.objects.filter(business=customer.business, customer=customer).order_by("created_at")
        opening = 0
        if start:
            before = rows.filter(created_at__date__lt=start).order_by("-created_at").first()
            opening = before.balance_after_htg if before else 0
            rows = rows.filter(created_at__date__gte=start)
        if end:
            rows = rows.filter(created_at__date__lte=end)
        entries = CustomerTransactionSerializer(rows, many=True).data
        closing = entries[-1]["balance_after_htg"] if entries else opening
        return Response({
            "customer": CustomerSerializer(customer).data,
            "from": start, "to": end,
            "opening_balance_htg": opening,
            "closing_balance_htg": closing,
            "entries": entries,
        })

    @action(detail=False, methods=["get"])
    def collections(self, request):
        """Recouvrement dashboard numbers."""
        base = Customer.objects.filter(business=request.user.business, is_active=True)
        totals = base.aggregate(
            total_owed=Sum("balance_htg", filter=Q(balance_htg__gt=0)),
            debtors=Count("id", filter=Q(balance_htg__gt=0)),
            blocked=Count("id", filter=Q(is_credit_blocked=True)),
            store_credit=Sum("store_credit_htg"),
        )
        top = base.filter(balance_htg__gt=0).order_by("-balance_htg")[:50]
        due = PaymentSchedule.objects.filter(
            business=request.user.business, is_paid=False, scheduled_date__lte=timezone.localdate()
        ).select_related("customer")[:50]
        return Response({
            "total_owed_htg": totals["total_owed"] or 0,
            "debtor_count": totals["debtors"],
            "blocked_count": totals["blocked"],
            "store_credit_outstanding_htg": totals["store_credit"] or 0,
            "debtors": CustomerListSerializer(top, many=True).data,
            "due_schedules": [
                {**PaymentScheduleSerializer(s).data, "customer_name": s.customer.name} for s in due
            ],
        })

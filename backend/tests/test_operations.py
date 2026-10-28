import json
import uuid
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts import roles
from apps.catalog.models import Product
from apps.customers.models import Customer
from apps.payments.models import PayLink

from .base import ApiTestCase


class CashSessionTests(ApiTestCase):
    def test_close_with_variance(self):
        session = self.open_drawer("1000")
        self.assertEqual(self.client.post("/api/v1/cash/sessions/open", {"opening_htg": 5}, format="json").status_code, 409)
        product = self.product(price="250")
        self.sale(lines=[{"product_id": str(product.pk), "quantity": 2}], payments=[{"method": "cash", "amount_htg": 500}])
        self.client.post(f"/api/v1/cash/sessions/{session['id']}/movements",
                         {"type": "cashOut", "amount_htg": 100, "description": "Transport"}, format="json")
        current = self.client.get("/api/v1/cash/sessions/current").json()["session"]
        self.assertEqual(current["drawer_expected_htg"], 1400.0)
        closed = self.client.post(f"/api/v1/cash/sessions/{session['id']}/close", {"counted_htg": 1350}, format="json")
        self.assertEqual(closed.json()["over_short_htg"], -50.0)
        self.assertEqual(self.client.get("/api/v1/notifications/unread-count").json()["unread"], 1)

    def test_required_drawer_blocks_cash_sales(self):
        self.settings.require_open_cash_session = True
        self.settings.save()
        product = self.product()
        response = self.sale(lines=[{"product_id": str(product.pk), "quantity": 1}],
                             payments=[{"method": "cash", "amount_htg": 100}])
        self.assertEqual(response.status_code, 409)


class SyncTests(ApiTestCase):
    def test_push_is_idempotent_and_pull_returns_changes(self):
        product = self.product(stock=10)
        sale_id = str(uuid.uuid4())
        ops = [
            {"op_id": "op-1", "kind": "sale", "payload": {"id": sale_id, "lines": [{"product_id": str(product.pk),
                                                                                     "quantity": 2}],
                                                          "payments": [{"method": "cash", "amount_htg": 200}]}},
            {"op_id": "op-2", "kind": "customer", "payload": {"id": str(uuid.uuid4()), "name": "Hors ligne"}},
            {"op_id": "op-3", "kind": "orderStatus", "payload": {"order_id": sale_id, "status": "pickedUp"}},
        ]
        first = self.client.post("/api/v1/sync/push", {"operations": ops}, format="json").json()["results"]
        self.assertEqual([r["status"] for r in first], ["applied", "applied", "failed"])
        second = self.client.post("/api/v1/sync/push", {"operations": ops}, format="json").json()["results"]
        self.assertTrue(all(r.get("replayed") for r in second))
        self.assertEqual(Product.objects.get(pk=product.pk).stock_quantity, 8)

        pull = self.client.get("/api/v1/sync/pull").json()
        self.assertEqual(len(pull["orders"]), 1)
        self.assertEqual(len(pull["customers"]), 1)
        since = pull["next_since"]
        product_id = str(product.pk)
        product.delete()
        later = self.client.get("/api/v1/sync/pull", {"since": since}).json()
        self.assertEqual(later["deleted"], [{"entity": "product", "id": product_id}])
        self.assertEqual(later["orders"], [])

    def test_push_respects_permissions(self):
        seller = self.client_for(self.make_staff(roles.SELLER))
        ops = [{"op_id": "x", "kind": "product", "payload": {"name": "Marteau", "price_htg": 10}}]
        result = seller.post("/api/v1/sync/push", {"operations": ops}, format="json").json()["results"][0]
        self.assertEqual(result["status"], "failed")


class PayLinkTests(ApiTestCase):
    def _webhook(self, event):
        import hashlib
        import hmac
        import time

        payload = json.dumps(event).encode()
        stamp = str(int(time.time()))
        sig = hmac.new(b"whsec_test", f"{stamp}.".encode() + payload, hashlib.sha256).hexdigest()
        return APIClient().post("/payments/webhook", payload, content_type="application/json",
                                HTTP_STRIPE_SIGNATURE=f"t={stamp},v1={sig}")

    @override_settings(STRIPE_SECRET_KEY="sk_test", STRIPE_WEBHOOK_SECRET="whsec_test")
    def test_paid_link_becomes_store_credit_once(self):
        customer = Customer.objects.create(business=self.business, name="Rose")
        fake = {"id": "cs_1", "url": "https://checkout.stripe.com/x", "order_usd_cents": 1000,
                "platform_fee_usd_cents": 115, "stripe_fee_usd_cents": 67, "total_usd_cents": 1182}
        with mock.patch("apps.payments.services.stripe.create_checkout", return_value=fake):
            link = self.client.post("/api/v1/paylinks", {"customer_id": str(customer.pk), "amount_htg": 1350},
                                    format="json")
        self.assertEqual(link.status_code, 201, link.content)
        event = {"id": "evt_1", "type": "checkout.session.completed",
                 "data": {"object": {"id": "cs_1", "payment_status": "paid", "amount_total": 1182,
                                     "metadata": {"kind": "paylink", "paylink": link.json()["id"]}}}}
        self.assertTrue(self._webhook(event).json()["paid"])
        self.assertTrue(self._webhook(event).json()["duplicate"])
        customer.refresh_from_db()
        self.assertEqual(customer.store_credit_htg, Decimal("1350.00"))
        self.assertEqual(PayLink.objects.get().status, "paidUnused")

    @override_settings(STRIPE_WEBHOOK_SECRET="whsec_test")
    def test_bad_signature(self):
        response = APIClient().post("/payments/webhook", b"{}", content_type="application/json",
                                    HTTP_STRIPE_SIGNATURE="t=1,v1=00")
        self.assertEqual(response.status_code, 400)

    def test_legacy_health_and_config(self):
        self.assertEqual(APIClient().get("/health").json(), {"ok": True})
        self.assertIn("stripe_configured", APIClient().get("/config").json())
        self.assertEqual(APIClient().get("/paid")["Content-Type"], "text/html; charset=utf-8")


class TimeclockTests(ApiTestCase):
    def test_punch_and_manual_edit(self):
        seller = self.make_staff(roles.SELLER)
        seller_client = self.client_for(seller)
        entry = seller_client.post("/api/v1/timeclock/clock-in").json()
        self.assertEqual(seller_client.post("/api/v1/timeclock/clock-in").json()["id"], entry["id"])
        self.assertIsNotNone(seller_client.post("/api/v1/timeclock/clock-out").json()["clock_out"])
        self.assertEqual(seller_client.patch(f"/api/v1/timeclock/{entry['id']}", {}, format="json").status_code, 403)
        new_in = (timezone.now() - timedelta(hours=2)).isoformat()
        edited = self.client.patch(f"/api/v1/timeclock/{entry['id']}", {"clock_in": new_in}, format="json").json()
        self.assertTrue(edited["is_manual"])
        self.assertIsNotNone(edited["original_clock_in"])
        overlap = self.client.post("/api/v1/timeclock/manual", {
            "staff": str(seller.pk), "clock_in": (timezone.now() - timedelta(hours=3)).isoformat(),
            "clock_out": (timezone.now() - timedelta(hours=1)).isoformat()}, format="json")
        self.assertEqual(overlap.status_code, 409)


class ReportTests(ApiTestCase):
    def test_summary_and_receivables(self):
        product = self.product(price="100")
        customer = Customer.objects.create(business=self.business, name="Paul")
        self.sale(lines=[{"product_id": str(product.pk), "quantity": 3}], customer_id=str(customer.pk),
                  payments=[{"method": "cash", "amount_htg": 100}], charge_remainder_to_credit=True)
        summary = self.client.get("/api/v1/reports/summary").json()
        self.assertEqual((summary["orders"], summary["gross_htg"], summary["cost_htg"]), (1, 300.0, 120.0))
        receivables = self.client.get("/api/v1/reports/receivables").json()
        self.assertEqual(receivables["buckets"]["0_30"], 200.0)
        self.assertEqual(self.client.get("/api/v1/dashboard").json()["orders_today"], 1)

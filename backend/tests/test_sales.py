import uuid
from decimal import Decimal

from apps.accounts import roles
from apps.cash.models import CashMovement
from apps.catalog.models import Product
from apps.customers.models import Customer
from apps.payments.models import CheckPayment

from .base import ApiTestCase


class SaleTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.nail = self.product("Clou", price="100", stock=10)

    def test_cash_sale_moves_stock_and_drawer(self):
        self.open_drawer()
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 3}],
                             payments=[{"method": "cash", "amount_htg": 300, "tendered_htg": 500}])
        self.assertEqual(response.status_code, 201, response.content)
        data = response.json()
        self.assertEqual(data["status"], "paid")
        self.assertEqual(data["total_htg"], 300.0)
        self.assertEqual(data["payments"][0]["change_htg"], 200.0)
        self.nail.refresh_from_db()
        self.assertEqual(self.nail.stock_quantity, 7)
        movement = CashMovement.objects.get(order_id=data["id"])
        self.assertEqual((movement.type, movement.amount_htg), ("cashIn", Decimal("300.00")))

    def test_replaying_the_same_sale_id_is_a_no_op(self):
        sale_id = str(uuid.uuid4())
        body = {"id": sale_id, "lines": [{"product_id": str(self.nail.pk), "quantity": 1}],
                "payments": [{"method": "cash", "amount_htg": 100}]}
        self.assertEqual(self.sale(**body).status_code, 201)
        again = self.sale(**body)
        self.assertEqual(again.status_code, 200)
        self.nail.refresh_from_db()
        self.assertEqual(self.nail.stock_quantity, 9)

    def test_client_total_is_never_trusted(self):
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 2}],
                             payments=[{"method": "cash", "amount_htg": 100}])
        self.assertEqual(response.status_code, 400)
        self.assertIn("Il reste", response.json()["error"])

    def test_service_fee_on_card_split(self):
        self.settings.service_fee_enabled = True
        self.settings.service_fee_percent = Decimal("10")
        self.settings.save()
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 2}],
                             payments=[{"method": "cash", "amount_htg": 100}, {"method": "card", "amount_htg": 120,
                                                                               "last_four": "4242"}])
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["total_htg"], 220.0)
        self.assertEqual(response.json()["payment_method"], "split")

    def test_partial_payment_charges_client_credit_and_collects_later(self):
        client = Customer.objects.create(business=self.business, name="Paul", phone="3712 3456",
                                         credit_limit_htg=Decimal("5000"))
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 5}], customer_id=str(client.pk),
                             payments=[{"method": "cash", "amount_htg": 200}], charge_remainder_to_credit=True)
        self.assertEqual(response.status_code, 201, response.content)
        order = response.json()
        self.assertEqual((order["status"], order["balance_due_htg"]), ("partiallyPaid", 300.0))
        client.refresh_from_db()
        self.assertEqual(client.balance_htg, Decimal("300.00"))

        collect = self.client.post(f"/api/v1/orders/{order['id']}/collect",
                                   {"payments": [{"method": "moncash", "amount_htg": 300}]}, format="json")
        self.assertEqual(collect.status_code, 200, collect.content)
        self.assertEqual((collect.json()["status"], collect.json()["balance_due_htg"]), ("paid", 0.0))
        client.refresh_from_db()
        self.assertEqual(client.balance_htg, Decimal("0.00"))

    def test_seller_cannot_grant_credit(self):
        seller = self.client_for(self.make_staff(roles.SELLER))
        client = Customer.objects.create(business=self.business, name="Paul")
        response = self.sale(client=seller, lines=[{"product_id": str(self.nail.pk), "quantity": 1}],
                             customer_id=str(client.pk), charge_remainder_to_credit=True)
        self.assertEqual(response.status_code, 403)

    def test_credit_limit(self):
        client = Customer.objects.create(business=self.business, name="Paul", credit_limit_htg=Decimal("50"))
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], customer_id=str(client.pk),
                             charge_remainder_to_credit=True)
        self.assertEqual(response.status_code, 409)

    def test_pickup_completes_and_status_rules(self):
        response = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], fulfillment_mode="pickup",
                             payments=[{"method": "cash", "amount_htg": 100}])
        self.assertEqual(response.json()["status"], "completed")
        delivery = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], fulfillment_mode="delivery",
                             delivery_location="Pétion-Ville", payments=[{"method": "cash", "amount_htg": 100}]).json()
        bad = self.client.post(f"/api/v1/orders/{delivery['id']}/status", {"status": "pickedUp"}, format="json")
        self.assertEqual(bad.status_code, 409)
        ok = self.client.post(f"/api/v1/orders/{delivery['id']}/status", {"status": "delivered"}, format="json")
        self.assertEqual(ok.json()["status"], "delivered")

    def test_discount_needs_approval_code_for_cashier(self):
        from apps.accounts.services import set_discount_code

        set_discount_code(self.settings, "4321")
        cashier = self.client_for(self.make_staff(roles.CASHIER))
        line = [{"product_id": str(self.nail.pk), "quantity": 1}]
        denied = self.sale(client=cashier, lines=line, discount_percent=10, payments=[{"method": "cash", "amount_htg": 90}])
        self.assertEqual(denied.status_code, 403)
        ok = self.sale(client=cashier, lines=line, discount_percent=10, discount_code="4321",
                       payments=[{"method": "cash", "amount_htg": 90}])
        self.assertEqual(ok.status_code, 201, ok.content)

    def test_price_override_needs_catalog_permission(self):
        seller = self.client_for(self.make_staff(roles.SELLER))
        line = [{"product_id": str(self.nail.pk), "quantity": 1, "unit_price_htg": 50}]
        self.assertEqual(self.sale(client=seller, lines=line, payments=[{"method": "cash", "amount_htg": 50}]).status_code, 403)
        ok = self.sale(lines=line, payments=[{"method": "cash", "amount_htg": 50}])
        self.assertTrue(ok.json()["lines"][0]["price_overridden"])

    def test_other_business_cannot_read_orders(self):
        from apps.accounts.services import register_business

        order = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}],
                          payments=[{"method": "cash", "amount_htg": 100}]).json()
        _, other_owner = register_business(firebase_uid="owner-2", business_name="Autre", owner_name="Autre Owner")
        other = self.client_for(other_owner)
        self.assertEqual(other.get(f"/api/v1/orders/{order['id']}").status_code, 404)
        self.assertEqual(other.get("/api/v1/orders").json()["count"], 0)


class CheckAndRefundTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.nail = self.product("Clou", price="100", stock=10)
        self.client_row = Customer.objects.create(business=self.business, name="Paul", phone="37123456")

    def _check_sale(self):
        return self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 2}], customer_id=str(self.client_row.pk),
                         payments=[{"method": "check", "amount_htg": 200,
                                    "check": {"number": "001", "bank": "Unibank", "payer_name": "Paul"}}]).json()

    def test_cleared_check_marks_order_paid(self):
        order = self._check_sale()
        self.assertEqual(order["status"], "checkPending")
        check = CheckPayment.objects.get()
        response = self.client.post(f"/api/v1/checks/{check.pk}/clear")
        self.assertEqual(response.json()["clearance_label"], "Chèque compensé par : Marie Owner")
        self.assertEqual(self.client.get(f"/api/v1/orders/{order['id']}").json()["status"], "paid")

    def test_refused_check_reopens_balance_and_charges_client(self):
        order = self._check_sale()
        check = CheckPayment.objects.get()
        self.client.post(f"/api/v1/checks/{check.pk}/refuse", {"reason": "Sans provision"}, format="json")
        detail = self.client.get(f"/api/v1/orders/{order['id']}").json()
        self.assertEqual((detail["status"], detail["balance_due_htg"]), ("partiallyPaid", 200.0))
        self.client_row.refresh_from_db()
        self.assertEqual(self.client_row.balance_htg, Decimal("200.00"))

    def test_cash_refund_restocks_and_needs_open_drawer(self):
        order = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 2}],
                          payments=[{"method": "cash", "amount_htg": 200}]).json()
        line_id = order["lines"][0]["id"]
        body = {"lines": [{"line_id": line_id, "quantity": 1}], "method": "cash", "reason": "Défaut"}
        self.assertEqual(self.client.post(f"/api/v1/orders/{order['id']}/refund", body, format="json").status_code, 409)
        self.open_drawer()
        response = self.client.post(f"/api/v1/orders/{order['id']}/refund", body, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["amount_htg"], 100.0)
        self.nail.refresh_from_db()
        self.assertEqual(self.nail.stock_quantity, 9)
        again = self.client.post(f"/api/v1/orders/{order['id']}/refund",
                                 {**body, "lines": [{"line_id": line_id, "quantity": 2}]}, format="json")
        self.assertEqual(again.status_code, 400)

    def test_store_credit_refund_then_spend(self):
        order = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], customer_id=str(self.client_row.pk),
                          payments=[{"method": "cash", "amount_htg": 100}]).json()
        self.client.post(f"/api/v1/orders/{order['id']}/refund",
                         {"lines": [{"line_id": order["lines"][0]["id"], "quantity": 1}], "method": "storeCredit",
                          "reason": "Retour"}, format="json")
        self.client_row.refresh_from_db()
        self.assertEqual(self.client_row.store_credit_htg, Decimal("100.00"))
        denied = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], customer_id=str(self.client_row.pk),
                           payments=[{"method": "storeCredit", "amount_htg": 100}])
        self.assertEqual(denied.status_code, 400)
        Customer.objects.filter(pk=self.client_row.pk).update(first_name="Paul", last_name="Pierre",
                                                               government_id="NIF-1")
        ok = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 1}], customer_id=str(self.client_row.pk),
                       payments=[{"method": "storeCredit", "amount_htg": 100}])
        self.assertEqual(ok.status_code, 201, ok.content)

    def test_cancel_restocks_unpaid_credit_sale(self):
        self.client_row.credit_limit_htg = None
        self.client_row.save()
        order = self.sale(lines=[{"product_id": str(self.nail.pk), "quantity": 4}], customer_id=str(self.client_row.pk),
                          charge_remainder_to_credit=True).json()
        response = self.client.post(f"/api/v1/orders/{order['id']}/cancel", {"reason": "Erreur"}, format="json")
        self.assertEqual(response.json()["status"], "cancelled")
        self.nail.refresh_from_db()
        self.client_row.refresh_from_db()
        self.assertEqual((self.nail.stock_quantity, self.client_row.balance_htg), (10, Decimal("0.00")))


class QuoteTests(ApiTestCase):
    def test_quote_converts_to_sale(self):
        product = self.product(stock=5)
        quote = self.client.post("/api/v1/quotes", {"lines": [{"product_id": str(product.pk), "quantity": 2}],
                                                     "client_name": "Rose"}, format="json").json()
        self.assertEqual(quote["total_htg"], 200.0)
        order = self.client.post(f"/api/v1/quotes/{quote['id']}/convert",
                                 {"payments": [{"method": "cash", "amount_htg": 200}]}, format="json")
        self.assertEqual(order.status_code, 201, order.content)
        self.assertEqual(self.client.get(f"/api/v1/quotes/{quote['id']}").json()["status"], "converted")
        self.assertEqual(Product.objects.get(pk=product.pk).stock_quantity, 3)

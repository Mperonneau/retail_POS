from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APIClient

from apps.catalog.models import Product, StockMovement
from apps.payments.providers import stripe
from apps.sales.models import Order, Quote
from apps.storefront import services
from apps.storefront.models import StorefrontRequest, StorefrontShop

from .base import ApiTestCase

SHOP_KEY = "k" * 40
PNG = ("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")


def publish_payload(**extra):
    return {
        "slug": "quincaillerie-zoe",
        "name": "Quincaillerie Zoé",
        "department": "Ouest",
        "categories": ["Quincaillerie", "Inconnu"],
        "settings": {"enabled": True, "accept_when_closed": True, "cover": PNG},
        "products": [
            {"id": "p1", "name": "Clou", "category": "Fixations", "price_htg": 25, "stock": 5, "track_stock": True},
            {"id": "p2", "name": "Tissu", "price_htg": 5, "stock": 200, "sale_mode": "roll", "roll_price_htg": 400,
             "roll_width": 100, "min_width": 10,
             "options": [{"id": "g1", "name": "Couleur", "required": True,
                          "choices": [{"id": "c1", "name": "Bleu", "delta_htg": 0}]}]},
            {"id": "bad", "name": "Sans prix", "price_htg": 0},
        ],
        **extra,
    }


class LegacyVitrineTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.public = APIClient()
        self.keyed = APIClient()
        self.keyed.credentials(HTTP_X_SHOP_KEY=SHOP_KEY)
        response = self.keyed.post("/storefront/shop/publish", publish_payload(), format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.published = response.json()
        self.shop = StorefrontShop.objects.get(slug="quincaillerie-zoe")

    def _order(self, kind="commande", lines=None, **extra):
        return self.public.post("/storefront/shops/quincaillerie-zoe/requests", {
            "kind": kind,
            "customer": {"name": "Rose", "phone": "+509 3712 3456"},
            "lines": lines or [{"product_id": "p1", "quantity": 2}],
            **extra,
        }, format="json")

    def test_publish_creates_catalog(self):
        self.assertEqual(self.published["products"], 2)
        self.assertEqual(self.shop.categories, ["Quincaillerie"])
        self.assertTrue(Product.objects.filter(business=self.shop.business, external_id="p2", sale_mode="roll").exists())
        again = self.keyed.post("/storefront/shop/publish", publish_payload(products=publish_payload()["products"][:1]),
                                format="json")
        self.assertEqual(again.json()["products"], 1)
        self.assertFalse(Product.objects.get(business=self.shop.business, external_id="p2").show_on_storefront)

    def test_slug_taken_by_another_key(self):
        other = APIClient()
        other.credentials(HTTP_X_SHOP_KEY="z" * 40)
        self.assertEqual(other.post("/storefront/shop/publish", publish_payload(), format="json").status_code, 409)
        self.assertFalse(other.get("/storefront/shop/slug?slug=quincaillerie-zoe").json()["available"])

    def test_directory_and_public_shop(self):
        directory = self.public.get("/storefront/shops?department=Ouest").json()
        self.assertEqual([r["slug"] for r in directory["results"]], ["quincaillerie-zoe"])
        self.assertIn("Artibonite", directory["departments"])
        shop = self.public.get("/storefront/shops/quincaillerie-zoe").json()
        self.assertEqual(len(shop["products"]), 2)
        self.assertTrue(shop["cover_url"].startswith("/storefront/photos/"))
        photo = self.public.get(shop["cover_url"])
        self.assertEqual(photo["Content-Type"], "image/png")

    def test_prices_are_recomputed_and_stock_is_held(self):
        response = self._order(lines=[{"product_id": "p1", "quantity": 2, "unit_htg": 1}])
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["total_htg"], 50.0)
        product = Product.objects.get(business=self.shop.business, external_id="p1")
        self.assertEqual(product.stock_quantity, 3)
        short = self._order(lines=[{"product_id": "p1", "quantity": 4}])
        self.assertEqual(short.status_code, 409)
        self.assertEqual(short.json()["error"], "Il reste 3 × Clou en stock.")

    def test_roll_requires_option_and_minimum(self):
        missing = self._order(lines=[{"product_id": "p2", "quantity": 1, "measure": "cut", "width": 20}])
        self.assertEqual(missing.json()["error"], "Choisissez « Couleur » pour Tissu.")
        short = self._order(lines=[{"product_id": "p2", "quantity": 1, "measure": "cut", "width": 5, "choices": ["c1"]}])
        self.assertEqual(short.json()["error"], "La longueur minimum pour Tissu est 10 po.")
        ok = self._order(lines=[{"product_id": "p2", "quantity": 1, "measure": "cut", "width": 20, "choices": ["c1"]}])
        self.assertEqual(ok.json()["lines"][0]["options_label"], "20 po, Bleu")

    def test_card_payment_turns_into_order_once(self):
        created = self._order().json()
        request_id = created["id"]
        total = stripe.price_card_charge(created["order_usd_cents"])["total_usd_cents"]
        intent = {"id": "pi_123", "status": "succeeded", "amount_received": total,
                  "metadata": {"reference": request_id, "kind": "storefront"}}
        self.assertTrue(services.settle_card_intent(request_id, intent))
        self.assertTrue(services.settle_card_intent(request_id, intent))
        request = StorefrontRequest.objects.get(pk=request_id)
        self.assertEqual(request.status, "paid")
        order = Order.objects.get(pk=request.order_id)
        self.assertEqual((order.source, order.total_htg, order.status), ("storefront", Decimal("50.00"), "paid"))
        product = Product.objects.get(business=self.shop.business, external_id="p1")
        self.assertEqual(product.stock_quantity, 3)
        view = self.public.get(f"/storefront/requests/{request_id}").json()
        self.assertEqual(view["order_status"], "paid")
        inbox = self.keyed.get("/storefront/shop/inbox").json()["requests"]
        self.assertEqual(inbox[0]["order_number"], order.number)

    def test_underpaid_intent_is_rejected(self):
        created = self._order().json()
        intent = {"id": "pi_1", "status": "succeeded", "amount_received": 1,
                  "metadata": {"reference": created["id"]}}
        with self.assertRaises(Exception):
            services.settle_card_intent(created["id"], intent)
        self.assertEqual(StorefrontRequest.objects.get(pk=created["id"]).status, "open")

    def test_lapsed_reservation_returns_stock(self):
        created = self._order().json()
        StorefrontRequest.objects.filter(pk=created["id"]).update(reserved_until=timezone.now() - timedelta(minutes=1))
        self.assertEqual(services.release_expired(), 1)
        product = Product.objects.get(business=self.shop.business, external_id="p1")
        self.assertEqual(product.stock_quantity, 5)
        self.assertEqual(StockMovement.objects.filter(product=product, kind="release").count(), 1)

    def test_devis_creates_quote(self):
        created = self._order(kind="devis").json()
        self.assertTrue(created["number"].startswith("DEV-"))
        self.assertTrue(Quote.objects.filter(business=self.shop.business, source="storefront").exists())
        product = Product.objects.get(business=self.shop.business, external_id="p1")
        self.assertEqual(product.stock_quantity, 5)

    def test_paused_shop_refuses_orders(self):
        StorefrontShop.objects.filter(pk=self.shop.pk).update(paused=True)
        self.assertEqual(self._order().status_code, 409)

    def test_phone_signup_and_orders(self):
        verify = self.public.post("/storefront/account/verify", {"phone": "37123456", "country": "HT", "code": "000"},
                                  format="json").json()
        self.assertFalse(verify["registered"])
        registered = self.public.post("/storefront/account/register",
                                      {"signup_token": verify["signup_token"], "name": "Rose Pierre"}, format="json")
        token = registered.json()["token"]
        self.assertEqual(registered.json()["account"]["phone"], "+50937123456")
        self.public.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        self._order()
        orders = self.public.get("/storefront/account/orders").json()["orders"]
        self.assertEqual(len(orders), 1)
        again = APIClient().post("/storefront/account/verify", {"phone": "+509 3712-3456", "country": "HT", "code": "1"},
                                 format="json").json()
        self.assertTrue(again["registered"])

    def test_pos_share_link_keeps_shop_prices(self):
        response = self.keyed.post("/storefront/shop/requests", {
            "kind": "devis", "reference": "Q-1", "discount_htg": 10,
            "lines": [{"product_id": "p1", "name": "Clou", "quantity": 4, "unit_htg": 20}],
        }, format="json").json()
        self.assertEqual(response["total_htg"], 70.0)
        again = self.keyed.post("/storefront/shop/requests", {
            "kind": "devis", "reference": "Q-1",
            "lines": [{"product_id": "p1", "name": "Clou", "quantity": 1, "unit_htg": 20}],
        }, format="json").json()
        self.assertEqual(again["id"], response["id"])
        self.assertEqual(again["total_htg"], 20.0)


class StaffVitrineTests(ApiTestCase):
    def test_settings_and_key_rotation(self):
        response = self.client.patch("/api/v1/storefront/shop", {"slug": "ma-boutique", "enabled": True,
                                                                  "department": "Nord"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertTrue(response.json()["public_url"].endswith("/ma-boutique"))
        key = self.client.post("/api/v1/storefront/shop/key").json()["shop_key"]
        keyed = APIClient()
        keyed.credentials(HTTP_X_SHOP_KEY=key)
        self.assertEqual(keyed.get("/storefront/shop/inbox").status_code, 200)
        product = self.product(stock=3, show_on_storefront=True)
        shop = APIClient().get("/storefront/shops/ma-boutique").json()
        self.assertEqual(shop["products"][0]["id"], str(product.pk))

from decimal import Decimal

from django.test import SimpleTestCase

from apps.catalog.models import Product
from apps.common.exceptions import ApiError
from apps.common.money import htg_to_usd_cents, money, whole_htg
from apps.payments.providers.stripe import price_card_charge, verify_signature
from apps.sales.services import compute_totals, status_after_full_payment

from .base import ApiTestCase


class TotalsTests(SimpleTestCase):
    def test_service_fee_only_when_paid_electronically(self):
        cash = compute_totals(Decimal("1000"), discount_percent=10, delivery_fee=200, tax_percent=10,
                              service_percent=5, electronic=False)
        card = compute_totals(Decimal("1000"), discount_percent=10, delivery_fee=200, tax_percent=10,
                              service_percent=5, electronic=True)
        self.assertEqual(cash.total, Decimal("1200.00"))
        self.assertEqual(card.total, Decimal("1250.00"))

    def test_fixed_discount_never_exceeds_subtotal(self):
        self.assertEqual(compute_totals(Decimal("100"), discount_amount=500).total, Decimal("0.00"))

    def test_status_after_full_payment(self):
        self.assertEqual(status_after_full_payment("pickup"), "completed")
        self.assertEqual(status_after_full_payment("inStore"), "paid")
        self.assertEqual(status_after_full_payment("delivery"), "paid")

    def test_money_helpers(self):
        self.assertEqual(money("12.345"), Decimal("12.35"))
        self.assertEqual(money("abc"), Decimal("0.00"))
        self.assertEqual(htg_to_usd_cents(1350, 135), 1000)
        self.assertEqual(whole_htg("99.5"), 100)

    def test_card_fee_grossed_up(self):
        pricing = price_card_charge(10000)
        self.assertEqual(pricing["platform_fee_usd_cents"], 250)
        self.assertGreaterEqual(pricing["total_usd_cents"] * (1 - 0.029) - 30, 10250 - 1)

    def test_stripe_signature(self):
        import hashlib
        import hmac
        import time

        payload = b'{"id":"evt_1"}'
        stamp = str(int(time.time()))
        sig = hmac.new(b"whsec", f"{stamp}.".encode() + payload, hashlib.sha256).hexdigest()
        self.assertTrue(verify_signature(payload, f"t={stamp},v1={sig}", "whsec"))
        self.assertFalse(verify_signature(payload, f"t={stamp},v1={'0' * 64}", "whsec"))
        self.assertFalse(verify_signature(payload, f"t=1,v1={sig}", "whsec"))


class LinePricingTests(ApiTestCase):
    def test_roll_cut_and_limits(self):
        from apps.catalog.pricing import price_line

        roll = self.product("Tissu", price="5", stock=500, sale_mode=Product.ROLL, roll_price_htg=Decimal("400"),
                            roll_width=100, min_width=10, limit_length=True)
        cut = price_line(roll, quantity=2, measure="cut", width=30)
        self.assertEqual(cut.unit_price, Decimal("150.00"))
        self.assertEqual(cut.stock_units, 60)
        whole = price_line(roll, quantity=1, measure="roll")
        self.assertEqual((whole.unit_price, whole.stock_units), (Decimal("400.00"), 100))
        with self.assertRaises(ApiError):
            price_line(roll, quantity=1, measure="cut", width=5)
        with self.assertRaises(ApiError):
            price_line(roll, quantity=1, measure="cut", width=101)

    def test_case_and_required_option(self):
        from apps.catalog.models import ProductOptionChoice, ProductOptionGroup
        from apps.catalog.pricing import price_line

        soda = self.product("Soda", price="50", stock=100, sale_mode=Product.CASE, case_price_htg=Decimal("500"),
                            units_per_case=12)
        group = ProductOptionGroup.objects.create(product=soda, name="Goût", required=True)
        cola = ProductOptionChoice.objects.create(group=group, name="Cola", price_delta_htg=Decimal("10"))
        with self.assertRaises(ApiError):
            price_line(soda, quantity=1, measure="case")
        line = price_line(soda, quantity=2, measure="case", choices=[str(cola.pk)])
        self.assertEqual(line.unit_price, Decimal("510.00"))
        self.assertEqual(line.stock_units, 24)
        self.assertEqual(line.options_label, "Caisse de 12, Cola")

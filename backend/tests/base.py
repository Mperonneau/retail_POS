from __future__ import annotations

from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts import roles
from apps.accounts.models import StaffMember, StaffSession
from apps.accounts.services import issue_session, register_business
from apps.catalog.models import Category, Product


class ApiTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.business, self.owner = register_business(firebase_uid="owner-1", business_name="Quincaillerie Test",
                                                      owner_name="Marie Owner")
        self.settings = self.business.settings
        self.location = self.owner.default_location
        self.client = self.client_for(self.owner)

    def make_staff(self, role: str, name: str = "Jean") -> StaffMember:
        return StaffMember.objects.create(business=self.business, full_name=name, role=role,
                                          default_location=self.location)

    def client_for(self, staff: StaffMember) -> APIClient:
        token, _ = issue_session(staff, kind=StaffSession.OWNER)
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Staff {token}")
        return client

    def product(self, name="Clou", price="100", stock=10, **extra) -> Product:
        category, _ = Category.objects.get_or_create(business=self.business, name="Général")
        return Product.objects.create(business=self.business, name=name, category=category,
                                      price_htg=Decimal(price), stock_quantity=stock, cost_htg=Decimal("40"), **extra)

    def open_drawer(self, opening="1000"):
        response = self.client.post("/api/v1/cash/sessions/open", {"opening_htg": opening}, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def sale(self, client=None, **data):
        response = (client or self.client).post("/api/v1/orders", data, format="json")
        return response


__all__ = ["ApiTestCase", "roles"]

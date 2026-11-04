from rest_framework.test import APIClient

from apps.accounts import roles
from apps.accounts.services import set_staff_pin

from .base import ApiTestCase


class DevicePinTests(ApiTestCase):
    def _pair(self):
        invite = self.client.post("/api/v1/devices/invites", {}, format="json")
        self.assertEqual(invite.status_code, 201, invite.content)
        device = APIClient()
        paired = device.post("/api/v1/devices/pair", {"code": invite.json()["code"].lower().replace("-", " "),
                                                       "device_name": "Caisse 1"}, format="json")
        self.assertEqual(paired.status_code, 201, paired.content)
        device.credentials(HTTP_AUTHORIZATION=f"Device {paired.json()['device_token']}")
        return device, invite.json()["code"]

    def test_pair_unlock_and_lockout(self):
        cashier = self.make_staff(roles.CASHIER, "Lina")
        set_staff_pin(cashier, "1234", actor=self.owner)
        device, code = self._pair()
        self.assertEqual(APIClient().post("/api/v1/devices/pair", {"code": code}, format="json").status_code, 400)

        unlocked = device.post("/api/v1/auth/pin", {"pin": "1234"}, format="json")
        self.assertEqual(unlocked.status_code, 200, unlocked.content)
        self.assertEqual(unlocked.json()["staff"]["role"], "cashier")
        staff_client = APIClient()
        staff_client.credentials(HTTP_AUTHORIZATION=f"Staff {unlocked.json()['token']}")
        self.assertEqual(staff_client.get("/api/v1/auth/me").status_code, 200)

        for _ in range(5):
            device.post("/api/v1/auth/pin", {"pin": "9999"}, format="json")
        locked = device.post("/api/v1/auth/pin", {"pin": "1234"}, format="json")
        self.assertIn(locked.status_code, (423, 429))

    def test_pins_are_unique_per_business(self):
        first = self.make_staff(roles.SELLER, "A")
        second = self.make_staff(roles.SELLER, "B")
        set_staff_pin(first, "4444", actor=self.owner)
        response = self.client.post(f"/api/v1/staff/{second.pk}/set-pin", {"pin": "4444"}, format="json")
        self.assertEqual(response.status_code, 409)

    def test_revoked_device_cannot_unlock(self):
        cashier = self.make_staff(roles.CASHIER)
        set_staff_pin(cashier, "1234", actor=self.owner)
        device, _ = self._pair()
        device_id = self.client.get("/api/v1/devices").json()[0]["id"]
        self.client.post(f"/api/v1/devices/{device_id}/revoke")
        self.assertEqual(device.post("/api/v1/auth/pin", {"pin": "1234"}, format="json").status_code, 401)


class PermissionTests(ApiTestCase):
    def test_role_defaults(self):
        seller = self.client_for(self.make_staff(roles.SELLER))
        cashier = self.client_for(self.make_staff(roles.CASHIER, "Caissier"))
        body = {"name": "Marteau", "price_htg": 500}
        self.assertEqual(seller.post("/api/v1/products", body, format="json").status_code, 403)
        self.assertEqual(cashier.post("/api/v1/products", body, format="json").status_code, 201)
        self.assertEqual(seller.get("/api/v1/reports/summary").status_code, 403)
        self.assertEqual(self.client.get("/api/v1/reports/summary").status_code, 200)

    def test_business_override_grants_permission(self):
        self.settings.role_permissions = {"seller": {"reports_view": True}}
        self.settings.save()
        seller = self.client_for(self.make_staff(roles.SELLER))
        self.assertEqual(seller.get("/api/v1/reports/summary").status_code, 200)

    def test_only_owner_manages_admins(self):
        admin = self.client_for(self.make_staff(roles.ADMIN, "Admin"))
        response = admin.post("/api/v1/staff", {"full_name": "Autre Admin", "role": "admin"}, format="json")
        self.assertEqual(response.status_code, 400)
        ok = self.client.post("/api/v1/staff", {"full_name": "Autre Admin", "role": "admin"}, format="json")
        self.assertEqual(ok.status_code, 201, ok.content)

    def test_unauthenticated_requests_are_rejected(self):
        self.assertEqual(APIClient().get("/api/v1/orders").status_code, 401)
        bad = APIClient()
        bad.credentials(HTTP_AUTHORIZATION="Staff nope")
        self.assertEqual(bad.get("/api/v1/orders").status_code, 401)

    def test_firebase_dev_token_resolves_owner(self):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer dev:owner-1",
                           HTTP_X_BUSINESS_ID=str(self.business.pk))
        self.assertEqual(client.get("/api/v1/auth/me").status_code, 200)

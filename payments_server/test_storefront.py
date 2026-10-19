"""Storefront store, pricing and payment settlement. No network."""

import base64
import os
import sys
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))

import server  # noqa: E402
from storefront import StorefrontError, StorefrontStore, _SHOP_TZ  # noqa: E402

KEY = "k" * 40
OTHER = "o" * 40
PNG = "data:image/png;base64," + base64.b64encode(b"\x89PNG fake").decode()


def _store() -> StorefrontStore:
    return StorefrontStore(tempfile.mkdtemp())


def _catalog(**settings):
    base = {
        "enabled": True,
        "paused": False,
        "accept_when_closed": False,
        "open_hour": 8,
        "close_hour": 18,
        "closed_weekdays": [7],
        "description": "Épicerie du quartier",
        "pickup_note": "Retrait au comptoir",
        "cover": PNG,
    }
    base.update(settings)
    return {
        "slug": "chez-marie",
        "name": "Chez Marie",
        "usd_rate": 130,
        "settings": base,
        "products": [
            {"id": "1", "name": "Riz", "category": "Alimentation", "price_htg": 650, "stock": 3, "track_stock": True},
            {
                "id": "2",
                "name": "T-shirt",
                "category": "Mode",
                "price_htg": 1300,
                "track_stock": False,
                "photo": PNG,
                "options": [
                    {
                        "id": "size",
                        "name": "Taille",
                        "required": True,
                        "multiple": False,
                        "choices": [
                            {"id": "s", "name": "Petit"},
                            {"id": "l", "name": "Grand", "delta_htg": 130},
                        ],
                    }
                ],
            },
            {"id": "3", "name": "Gratuit", "price_htg": 0},
        ],
    }


OPEN = datetime(2026, 10, 19, 10, 0, tzinfo=_SHOP_TZ)  # Monday 10h
SUNDAY = datetime(2026, 10, 18, 10, 0, tzinfo=_SHOP_TZ)
CUSTOMER = {"name": "Jean", "phone": "+509 3700 0000"}


def test_publish_and_public_shop():
    store = _store()
    result = store.publish(KEY, _catalog())
    assert result["products"] == 2, result
    shop = store.public_shop("chez-marie", OPEN)
    assert shop["name"] == "Chez Marie"
    assert shop["usd_rate"] == 130
    assert shop["availability"]["is_open_now"] and shop["availability"]["accepts_orders"]
    assert shop["cover_url"].startswith("/storefront/photos/")
    raw, mime = store.read_photo(shop["cover_url"].rsplit("/", 1)[1])
    assert raw.startswith(b"\x89PNG") and mime == "image/png"
    assert shop["categories"] == ["Alimentation", "Mode"]
    assert shop["products"][0]["max_quantity"] == 3


def test_slug_is_owned_by_first_key():
    store = _store()
    store.publish(KEY, _catalog())
    try:
        store.publish(OTHER, _catalog())
        raise AssertionError("slug taken")
    except StorefrontError as exc:
        assert exc.status == 409
    assert not store.slug_available(OTHER, "chez-marie")
    renamed = _catalog()
    renamed["slug"] = "marie-shop"
    store.publish(KEY, renamed)
    assert store.slug_available(OTHER, "chez-marie")


def test_directory_lists_enabled_shops_by_department():
    store = _store()
    store.publish(KEY, _catalog(city="Pétion-Ville", department="Ouest"))
    other = _catalog()
    other["slug"] = "marche-nord"
    other["name"] = "Marché Nord"
    other["settings"] = {**other["settings"], "city": "Cap-Haïtien", "department": "Nord"}
    store.publish(OTHER, other)
    hidden = _catalog(enabled=False)
    hidden["slug"] = "fermee"
    hidden["name"] = "Fermée"
    store.publish("h" * 40, hidden)
    bogus = _catalog()
    bogus["slug"] = "sans-region"
    bogus["name"] = "Sans région"
    bogus["department"] = "Mars"
    store.publish("b" * 40, bogus)

    listed = store.directory(now=OPEN)
    names = [row["name"] for row in listed["results"]]
    assert names == ["Chez Marie", "Marché Nord", "Sans région"], names
    assert "Fermée" not in names
    assert listed["departments"][0] == "Artibonite"
    assert len(listed["departments"]) == 10
    marie = listed["results"][0]
    assert marie["city"] == "Pétion-Ville" and marie["department"] == "Ouest"
    assert marie["is_open_now"] is True
    assert store.directory("Nord", OPEN)["results"][0]["slug"] == "marche-nord"
    assert store.directory("Mars")["results"] == []
    assert store.public_shop("sans-region", OPEN)["department"] == ""


def test_disabled_shop_is_hidden():
    store = _store()
    store.publish(KEY, _catalog(enabled=False))
    try:
        store.public_shop("chez-marie", OPEN)
        raise AssertionError("disabled shop")
    except StorefrontError as exc:
        assert exc.status == 404


def test_server_prices_order_with_options():
    store = _store()
    store.publish(KEY, _catalog())
    request = store.create_request(
        "chez-marie",
        {
            "kind": "commande",
            "customer": CUSTOMER,
            "lines": [
                {"product_id": "1", "quantity": 2, "unit_htg": 1},
                {"product_id": "2", "quantity": 1, "choices": ["l"]},
            ],
        },
        OPEN,
    )
    assert request["total_htg"] == 650 * 2 + 1430, request
    assert request["order_usd_cents"] == 2100, request
    assert request["moncash_htg"] == 2730
    assert request["lines"][1]["options_label"] == "Grand"
    assert request["status"] == "open" and request["number"].startswith("CMD-")


def test_order_rules():
    store = _store()
    store.publish(KEY, _catalog())

    def fails(payload, now=OPEN):
        try:
            store.create_request("chez-marie", payload, now)
        except StorefrontError as exc:
            return exc.message
        raise AssertionError(f"should fail: {payload}")

    line = [{"product_id": "1", "quantity": 1}]
    assert "Il reste 3" in fails({"kind": "commande", "customer": CUSTOMER, "lines": [{"product_id": "1", "quantity": 4}]})
    assert "Taille" in fails({"kind": "commande", "customer": CUSTOMER, "lines": [{"product_id": "2", "quantity": 1}]})
    assert "nom" in fails({"kind": "commande", "customer": {"phone": "37000000"}, "lines": line})
    assert "téléphone" in fails({"kind": "commande", "customer": {"name": "Jean"}, "lines": line})
    assert "fermée" in fails({"kind": "commande", "customer": CUSTOMER, "lines": line}, SUNDAY)
    devis = store.create_request("chez-marie", {"kind": "devis", "customer": CUSTOMER, "lines": line}, SUNDAY)
    assert devis["number"].startswith("DEV-")


def test_paused_shop_rejects_orders():
    store = _store()
    store.publish(KEY, _catalog(paused=True))
    try:
        store.create_request("chez-marie", {"kind": "devis", "customer": CUSTOMER, "lines": [{"product_id": "1", "quantity": 1}]}, OPEN)
        raise AssertionError("paused")
    except StorefrontError as exc:
        assert exc.status == 409


def test_shop_request_and_inbox():
    store = _store()
    store.publish(KEY, _catalog())
    shared = store.create_shop_request(
        KEY,
        {
            "kind": "devis",
            "reference": "q-1",
            "number": "QTE-2026-0001",
            "discount_htg": 100,
            "customer": {"name": "Paul", "phone": "37000001"},
            "lines": [{"product_id": "1", "name": "Riz", "quantity": 2, "unit_htg": 600}],
        },
    )
    assert shared["number"] == "QTE-2026-0001" and shared["total_htg"] == 1100
    again = store.create_shop_request(
        KEY,
        {"kind": "devis", "reference": "q-1", "lines": [{"name": "Riz", "quantity": 1, "unit_htg": 600}]},
    )
    assert again["id"] == shared["id"] and again["total_htg"] == 600
    inbox = store.inbox(KEY)
    assert len(inbox) == 1 and inbox[0]["source"] == "pos"
    assert store.inbox(OTHER) == []


def test_card_settlement_checks_reference_and_amount():
    previous = server.STORE
    server.STORE = _store()
    try:
        server.STORE.publish(KEY, _catalog())
        request = server.STORE.create_request(
            "chez-marie",
            {"kind": "commande", "customer": CUSTOMER, "lines": [{"product_id": "1", "quantity": 1}]},
            OPEN,
        )
        expected = server.price_card_charge(request["order_usd_cents"])["total_usd_cents"]
        intent = {"id": "pi_1", "status": "succeeded", "amount_received": expected, "metadata": {"reference": request["id"]}}
        for bad in (
            {**intent, "status": "requires_payment_method"},
            {**intent, "amount_received": expected - 1},
            {**intent, "metadata": {"reference": "other"}},
        ):
            try:
                server._settle_intent(request["id"], bad)
                raise AssertionError(f"should refuse {bad}")
            except server.PaymentError:
                pass
        assert server.STORE.get_request(request["id"])["status"] == "open"
        paid = server._settle_intent(request["id"], intent)
        assert paid["status"] == "paid" and paid["payment_method"] == "card"
        try:
            server.STORE.payable(request["id"])
            raise AssertionError("already paid")
        except StorefrontError as exc:
            assert exc.status == 409
        assert server.STORE.inbox(KEY)[0]["payment"]["amount"] == expected
    finally:
        server.STORE = previous


def test_known_photo_paths_are_reused_or_reported_missing():
    store = _store()
    store.publish(KEY, _catalog())
    cover = store.public_shop("chez-marie", OPEN)["cover_url"]
    again = _catalog(cover=cover)
    again["products"][1]["photo"] = "/storefront/photos/" + "a" * 32 + ".png"
    result = store.publish(KEY, again)
    assert result["missing_photos"] == ["/storefront/photos/" + "a" * 32 + ".png"], result
    assert store.public_shop("chez-marie", OPEN)["cover_url"] == cover


def test_data_survives_reload():
    folder = tempfile.mkdtemp()
    store = StorefrontStore(folder)
    store.publish(KEY, _catalog())
    reloaded = StorefrontStore(folder)
    assert reloaded.public_shop("chez-marie", OPEN)["name"] == "Chez Marie"


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok")

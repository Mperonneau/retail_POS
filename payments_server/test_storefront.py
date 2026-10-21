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
    assert listed["categories"] == []


def test_business_categories_keep_several_and_list_only_used():
    store = _store()
    store.publish(
        KEY,
        _catalog(categories=["Supermarché", "Supermarché", "Inconnu", "Quincaillerie"]),
    )
    shop = store.public_shop("chez-marie", OPEN)
    assert shop["business_categories"] == ["Supermarché", "Quincaillerie"]
    other = _catalog()
    other["slug"] = "fripe"
    other["name"] = "Fripe"
    other["categories"] = ["Friperie", "Vêtements"]
    store.publish(OTHER, other)
    listed = store.directory(now=OPEN)
    assert listed["categories"] == ["Supermarché", "Vêtements", "Friperie", "Quincaillerie"]
    cards = {row["name"]: row["categories"] for row in listed["results"]}
    assert cards["Chez Marie"] == ["Supermarché", "Quincaillerie"]
    assert cards["Fripe"] == ["Friperie", "Vêtements"]


def test_unknown_session_still_places_the_order():
    store = _store()
    store.publish(KEY, _catalog())
    assert store.account_phone("") == ""
    assert store.account_phone("session-oubliée") == ""
    request = store.create_request(
        "chez-marie",
        {"kind": "commande", "customer": CUSTOMER, "lines": [{"product_id": "1", "quantity": 1}]},
        OPEN,
        account_phone=store.account_phone("session-oubliée"),
    )
    assert request["number"].startswith("CMD-")
    assert request["customer_name"] == CUSTOMER["name"]


def test_account_login_and_orders():
    store = _store()
    store.publish(KEY, _catalog())
    created = store.open_account("50937001111", "1234", "Marie")
    token = created["token"]
    assert created["account"]["name"] == "Marie"
    try:
        store.open_account("50937001111", "0000")
        raise AssertionError("bad pin")
    except StorefrontError as exc:
        assert exc.status == 401
    again = store.open_account("+509 3700 1111", "1234")
    assert again["account"]["name"] == "Marie"
    store.create_request(
        "chez-marie",
        {"kind": "devis", "customer": CUSTOMER, "lines": [{"product_id": "1", "quantity": 1}]},
        OPEN,
        account_phone=store.phone_for_token(token),
    )
    orders = store.account_orders(token)
    assert len(orders) == 1 and orders[0]["kind"] == "devis"
    assert orders[0]["shop_name"] == "Chez Marie"
    assert store.account_orders(again["token"])[0]["id"] == orders[0]["id"]
    renamed = store.update_account(token, "Marie Joseph")
    assert renamed["name"] == "Marie Joseph"
    reloaded = StorefrontStore(store.data_dir)
    assert reloaded.account_for_token(token)["name"] == "Marie Joseph"


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


def test_roll_and_case_are_priced_from_the_choice():
    store = _store()
    catalog = _catalog()
    catalog["products"].extend(
        [
            {
                "id": "roll",
                "name": "Tissu",
                "price_htg": 15,
                "sale_mode": "roll",
                "roll_price_htg": 750,
                "roll_width": 60,
                "min_width": 12,
                "stock": 180,
                "track_stock": True,
            },
            {
                "id": "case",
                "name": "Eau",
                "price_htg": 40,
                "sale_mode": "case",
                "case_price_htg": 800,
                "units_per_case": 24,
                "stock": 72,
                "track_stock": True,
            },
        ]
    )
    store.publish(KEY, catalog)
    shop = store.public_shop("chez-marie", OPEN)
    roll = next(p for p in shop["products"] if p["id"] == "roll")
    assert roll["sale_mode"] == "roll" and roll["min_width"] == 12 and roll["stock"] == 180
    request = store.create_request(
        "chez-marie",
        {
            "kind": "commande",
            "customer": CUSTOMER,
            "lines": [
                {"product_id": "roll", "quantity": 1, "measure": "cut", "width": 36},
                {"product_id": "roll", "quantity": 1, "measure": "roll"},
                {"product_id": "case", "quantity": 1, "measure": "case"},
                {"product_id": "case", "quantity": 2, "measure": "unit"},
            ],
        },
        OPEN,
    )
    assert request["lines"][0]["unit_htg"] == 540
    assert request["lines"][0]["options_label"] == "36 po"
    assert request["lines"][0]["stock_units"] == 36
    assert request["lines"][1]["unit_htg"] == 750 and request["lines"][1]["stock_units"] == 60
    assert request["lines"][1]["options_label"] == "Longueur entière"
    assert request["lines"][2]["options_label"] == "Caisse de 24"
    assert request["lines"][2]["stock_units"] == 24
    assert request["lines"][3]["unit_htg"] == 40
    assert request["total_htg"] == 540 + 750 + 800 + 80, request

    def fails(lines):
        try:
            store.create_request(
                "chez-marie",
                {"kind": "commande", "customer": CUSTOMER, "lines": lines},
                OPEN,
            )
        except StorefrontError as exc:
            return exc.status
        raise AssertionError("accepted")

    assert fails([{"product_id": "roll", "quantity": 1, "measure": "cut", "width": 8}]) == 400
    assert fails([{"product_id": "roll", "quantity": 1}]) == 400
    assert fails([{"product_id": "roll", "quantity": 4, "measure": "roll"}]) == 409


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


def test_phone_code_creates_account_with_country():
    store = _store()
    assert store.request_code("3700 1111", "ht") == {"sent": True}
    checked = store.verify_code("37001111", "HT", "000000")
    assert checked["registered"] is False
    created = store.register_account(checked["signup_token"], "Marie Joseph", "")
    assert created["account"]["name"] == "Marie Joseph"
    assert created["account"]["phone"] == "+50937001111"
    assert created["account"]["country"] == "HT"
    assert created["account"]["email"] == ""
    try:
        store.register_account(checked["signup_token"], "Marie Joseph", "")
        raise AssertionError("signup reused")
    except StorefrontError as exc:
        assert exc.status == 401
    store.request_code("+509 3700 1111", "HT")
    again = store.verify_code("50937001111", "HT", "123456")
    assert again["registered"] is True
    assert again["account"]["name"] == "Marie Joseph"
    assert again["token"]
    with_mail = _store()
    with_mail.request_code("0612345678", "FR")
    pending = with_mail.verify_code("0612345678", "FR", "999999")
    saved = with_mail.register_account(pending["signup_token"], "Jean Pierre", "jean@exemple.fr")
    assert saved["account"]["country"] == "FR"
    assert saved["account"]["phone"] == "+33612345678"
    assert saved["account"]["email"] == "jean@exemple.fr"
    try:
        with_mail.register_account("nope", "Jean Pierre", "pas-un-email")
        raise AssertionError("email")
    except StorefrontError as exc:
        assert exc.status == 400


def test_phone_code_rejects_bad_input():
    store = _store()
    store.request_code("37001111", "HT")
    assert store.verify_code("37001111", "HT", "111111")["registered"] is False
    try:
        store.verify_code("37001111", "HT", "   ")
        raise AssertionError("empty code")
    except StorefrontError as exc:
        assert exc.status == 400
    try:
        store.request_code("37001111", "ZZ")
        raise AssertionError("country")
    except StorefrontError as exc:
        assert exc.status == 400
    try:
        store.request_code("2125551234", "DO")
        raise AssertionError("prefix")
    except StorefrontError as exc:
        assert exc.status == 400
    assert store.request_code("8095551234", "DO")["sent"] is True
    try:
        store.register_account("missing", "A", "")
        raise AssertionError("short name")
    except StorefrontError as exc:
        assert exc.status in (400, 401)


def test_existing_account_returns_home_after_code():
    store = _store()
    store.open_account("50937001111", "1234", "Marie")
    store.request_code("37001111", "HT")
    again = store.verify_code("37001111", "HT", "424242")
    assert again["registered"] is True
    assert again["account"]["name"] == "Marie"
    assert again["account"]["country"] == "HT"


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

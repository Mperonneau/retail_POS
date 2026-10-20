"""Catalogue extraction stays a reviewable draft, without calling Claude."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from catalog_import import CatalogImportError, _extract_json, normalize_draft


def test_prices_and_missing_stock_stay_reviewable():
    draft, report = normalize_draft(
        {
            "categories": [
                {
                    "name": "Alimentation",
                    "items": [
                        {
                            "name": "Riz Blanc 25kg",
                            "price_htg": 3200,
                            "price_source": "HTG",
                            "barcode": "123 456",
                            "unit": "u",
                            "stock": None,
                            "option_groups": [
                                {
                                    "name": "Sac",
                                    "kind": "size",
                                    "required": True,
                                    "multiple": False,
                                    "choices": [{"name": "25 kg", "price_delta_htg": 0}],
                                }
                            ],
                        },
                        {"name": "Riz Blanc 25kg", "price_htg": 3000},
                        {"name": "Sucre", "price_htg": 0, "stock": "beaucoup"},
                    ],
                }
            ],
            "report": [],
        },
        usd_rate=135,
        currency_mode="htg",
    )
    items = draft["categories"][0]["items"]
    assert [item["name"] for item in items] == ["Riz Blanc 25kg", "Sucre"]
    assert items[0]["barcode"] == "123456"
    assert items[0]["stock"] is None
    assert items[0]["option_groups"][0]["kind"] == "size"
    assert any("deux fois" in row["message"] for row in report)
    assert any("Prix manquant" in row["message"] for row in report)
    assert any("Quantité illisible" in row["message"] for row in report)


def test_truncated_json_is_closed():
    raw = '{"categories":[{"name":"Boissons","items":[{"name":"Eau","price_htg":40}]}]'
    data = _extract_json(raw)
    assert data["categories"][0]["items"][0]["name"] == "Eau"


def test_empty_upload_is_refused():
    try:
        from catalog_import import JOBS
        JOBS.start({"files": [], "currency_mode": "htg"})
    except CatalogImportError as exc:
        assert "document" in exc.message
    else:
        raise AssertionError("empty upload should fail")


if __name__ == "__main__":
    test_prices_and_missing_stock_stay_reviewable()
    test_truncated_json_is_closed()
    test_empty_upload_is_refused()
    print("ok")

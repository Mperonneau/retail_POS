"""Catalogue extraction stays a reviewable draft, without calling Claude."""
import io
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(__file__))

from catalog_import import CatalogImportError, _extract_json, _file_block, normalize_draft


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
    assert items[0]["sale_mode"] == "piece"
    assert items[0]["description"] == ""
    assert items[0]["discount_percent"] == 0
    assert items[0]["option_groups"][0]["kind"] == "size"
    assert any("deux fois" in row["message"] for row in report)
    assert any("Prix manquant" in row["message"] for row in report)
    assert any("Quantité illisible" in row["message"] for row in report)


def test_sale_mode_description_and_custom_category():
    draft, report = normalize_draft(
        {
            "categories": [
                {
                    "name": "quincaillerie",
                    "items": [
                        {
                            "name": "Tissu coton",
                            "price_htg": 15,
                            "sale_mode": "roll",
                            "roll_price_htg": 750,
                            "roll_width": 60,
                            "min_width": 12,
                            "description": "Coton vendu à la longueur.",
                            "cost_htg": 8,
                            "barcode": "TIS-1",
                            "discount_percent": 10,
                            "unit": "m",
                            "stock": 180,
                        }
                    ],
                },
                {
                    "name": "Outils électriques",
                    "items": [
                        {
                            "name": "Perceuse",
                            "price_htg": 4500,
                            "sale_mode": "piece",
                            "description": "Perceuse filaire 500 W.",
                        }
                    ],
                },
                {
                    "name": "Boissons",
                    "items": [
                        {
                            "name": "Eau 500 ml",
                            "price_htg": 40,
                            "sale_mode": "caisse",
                            "case_price_htg": 800,
                            "units_per_case": 24,
                        }
                    ],
                },
                {
                    "name": "",
                    "items": [
                        {
                            "name": "Ruban",
                            "price_htg": 8,
                            "roll_price_htg": 250,
                            "roll_width": 36,
                            "description": "Ruban adhésif.",
                        },
                        {
                            "name": "Câble incomplet",
                            "price_htg": 20,
                            "sale_mode": "roll",
                        },
                    ],
                },
            ],
            "report": [],
        },
        usd_rate=135,
        currency_mode="htg",
        known_categories=["Quincaillerie", "Boissons"],
    )
    by_name = {
        item["name"]: (category["name"], item)
        for category in draft["categories"]
        for item in category["items"]
    }
    rayon, tissu = by_name["Tissu coton"]
    assert rayon == "Quincaillerie"
    assert tissu["sale_mode"] == "roll"
    assert tissu["price_htg"] == 15
    assert tissu["roll_price_htg"] == 750
    assert tissu["roll_width"] == 60
    assert tissu["min_width"] == 12
    assert tissu["case_price_htg"] == 0
    assert tissu["description"] == "Coton vendu à la longueur."
    assert tissu["cost_htg"] == 8
    assert tissu["barcode"] == "TIS-1"
    assert tissu["discount_percent"] == 10
    assert tissu["unit"] == "u"
    assert tissu["stock"] == 180

    custom, perceuse = by_name["Perceuse"]
    assert custom == "Outils électriques"
    assert perceuse["sale_mode"] == "piece"
    assert perceuse["description"] == "Perceuse filaire 500 W."
    assert perceuse["roll_width"] == 0

    drinks, water = by_name["Eau 500 ml"]
    assert drinks == "Boissons"
    assert water["sale_mode"] == "case"
    assert water["price_htg"] == 40
    assert water["case_price_htg"] == 800
    assert water["units_per_case"] == 24
    assert water["roll_price_htg"] == 0

    other, ribbon = by_name["Ruban"]
    assert other == "Autre"
    assert ribbon["sale_mode"] == "roll"
    assert ribbon["min_width"] == 1
    assert ribbon["description"] == "Ruban adhésif."

    _, cable = by_name["Câble incomplet"]
    assert cable["sale_mode"] == "roll"
    assert any("longueur entière" in row["message"].lower() for row in report)
    assert any("Longueur entière manquante" in row["message"] for row in report)


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


def _zip(files: dict[str, str]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as archive:
        for path, content in files.items():
            archive.writestr(path, content)
    return buf.getvalue()


def test_excel_csv_and_word_become_text():
    sheet = _zip({
        "xl/sharedStrings.xml": "<sst><si><t>Riz blanc 25kg</t></si></sst>",
        "xl/worksheets/sheet1.xml": (
            "<worksheet><sheetData>"
            '<row><c t="s"><v>0</v></c><c><v>3200</v></c></row>'
            "</sheetData></worksheet>"
        ),
    })
    excel = _file_block("prix.xlsx", "application/octet-stream", sheet)
    assert excel["type"] == "text"
    assert "Riz blanc 25kg" in excel["text"]
    assert "3200" in excel["text"]

    csv = _file_block("prix.csv", "text/csv", "Savon,150\n".encode("utf-8"))
    assert "Savon" in csv["text"]

    word = _zip({
        "word/document.xml": (
            "<document><body><p><r><t>Huile végétale 600 HTG</t></r></p></body></document>"
        ),
    })
    doc = _file_block(
        "liste.docx",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        word,
    )
    assert "Huile végétale" in doc["text"]

    old = _file_block("ancien.xls", "application/vnd.ms-excel", "Riz 25kg 3200".encode("utf-16le"))
    assert "Riz" in old["text"]


if __name__ == "__main__":
    test_prices_and_missing_stock_stay_reviewable()
    test_sale_mode_description_and_custom_category()
    test_truncated_json_is_closed()
    test_empty_upload_is_refused()
    test_excel_csv_and_word_become_text()
    print("ok")

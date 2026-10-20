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
    test_truncated_json_is_closed()
    test_empty_upload_is_refused()
    test_excel_csv_and_word_become_text()
    print("ok")

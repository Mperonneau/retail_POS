"""Retail catalogue extraction through the Claude Messages API.

Same endpoint, key and model as the Tabkreyol menu import. The prompt asks
for shop products (price, barcode, stock, options) instead of a restaurant menu.
"""
from __future__ import annotations

import base64
import io
import json
import os
import re
import secrets
import threading
import time
import unicodedata
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from typing import Any

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
MAX_FILES = 6
MAX_FILE_BYTES = 4_000_000
MAX_TOKENS = 16384
_KINDS = {"size", "color", "extra", "other"}

SYSTEM_PROMPT = """Tu es un extracteur de catalogue pour une caisse de détail en Haïti.
Tu lis UN document (photo de liste de prix, facture, PDF ou tableau) et tu
renvoies UNIQUEMENT un JSON valide, sans markdown, sans commentaire.

Schéma exact :
{
  "categories": [
    {
      "name": "string",
      "items": [
        {
          "name": "string",
          "sale_mode": "piece|roll|case",
          "price_htg": 0,
          "price_source": "HTG|USD",
          "roll_price_htg": 0,
          "roll_width": 0,
          "min_width": 0,
          "case_price_htg": 0,
          "units_per_case": 0,
          "cost_htg": 0,
          "barcode": "",
          "unit": "u",
          "stock": null,
          "discount_percent": 0,
          "description": "",
          "option_groups": [
            {
              "name": "string",
              "kind": "size|color|extra|other",
              "required": false,
              "multiple": false,
              "choices": [{"name": "string", "price_delta_htg": 0}]
            }
          ]
        }
      ]
    }
  ],
  "report": [
    {"severity": "error|warning|info", "message": "string en français", "item_name": ""}
  ]
}

Règles :
- Extrais TOUS les produits visibles. N'invente aucun article absent du document.
- Remplis chaque champ que le document permet de lire. Omets un champ quand le document ne le donne pas : pas de 0, pas de chaîne vide, pas de null, pas de option_groups vide.
- JSON compact, sans retour à la ligne dans les chaînes.
- price_htg, roll_price_htg, case_price_htg, price_delta_htg et cost_htg sont des montants en GOURDES entières.
- Si un prix est en USD, convertis-le en HTG avec le taux fourni (arrondi à l'entier) et mets price_source à USD.
- sale_mode "piece" : un seul prix pour une pièce. price_htg est ce prix. Les champs de longueur et de caisse restent à 0.
- sale_mode "roll" : le document vend au pouce ou à la longueur. price_htg est le prix d'un pouce. roll_price_htg est le prix de la longueur entière. roll_width est cette longueur en pouces. min_width est la plus petite longueur acceptée, en pouces. Si le minimum n'est pas écrit, mets 1.
- sale_mode "case" : le document donne un prix de caisse (ou carton) et un prix à l'unité. price_htg est le prix d'une unité. case_price_htg est le prix d'une caisse. units_per_case est le nombre d'unités dans la caisse. Le prix d'une unité n'est pas le prix de la caisse divisé par le nombre.
- Un seul prix, sans mention de pouce ni de caisse, reste "piece". N'invente pas un mode.
- Une taille, une couleur ou un supplément est une option, pas un sale_mode.
- cost_htg reprend le prix d'achat ou le coût s'il est écrit, sinon 0.
- barcode reprend le code-barres, le SKU ou la référence imprimée, sinon "".
- unit est u, kg, L ou paquet. Défaut u. Le stock d'un produit au pouce est un nombre de pouces : laisse unit à u.
- stock : quantité entière si le document la donne, sinon null. N'invente pas un stock.
- discount_percent : le rabais en pourcentage s'il est écrit, sinon 0.
- description : le texte descriptif écrit pour ce produit, jusqu'à 600 caractères. S'il n'y en a pas, "". N'invente pas de description.
- name de la catégorie : le rayon écrit dans le document. Le message utilisateur liste les catégories déjà utilisées par ce magasin. Si le rayon correspond à l'une d'elles, reprends l'orthographe du magasin. Si ce rayon n'existe pas dans le magasin, garde le nom du document tel quel : il devient une catégorie de ce magasin seulement. Ne le remplace pas par un rayon proche. Utilise "Autre" seulement quand le document ne donne aucun rayon.
- Tailles ou conditionnements → kind "size". Couleurs → "color". Suppléments payants → "extra". Le reste → "other".
- Ignore adresse, téléphone, slogans, totaux de facture et lignes qui ne sont pas des produits.
- Signale dans report : prix manquants, longueur ou caisse incomplète, conversion USD, doublons, quantité illisible.
- Si rien n'est lisible, categories=[] et un report de sévérité error.
- Réponds en JSON compact uniquement.
"""


class CatalogImportError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


def _api_key() -> str:
    return (os.environ.get("CLAUDE_API_SECRET_KEY") or "").strip()


def _model() -> str:
    return (os.environ.get("CLAUDE_MODEL") or "claude-sonnet-4-5").strip()


def _norm(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").strip().lower())


def _fold(value: str) -> str:
    text = unicodedata.normalize("NFKD", value or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", text.strip().lower())


def _int_amount(value: object) -> int:
    try:
        return max(0, int(round(float(value or 0))))
    except (TypeError, ValueError):
        return 0


def _whole(value: object) -> int | None:
    if value in ("", None):
        return None
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return None


def _explicit_sale_mode(value: object) -> str | None:
    folded = _fold(str(value or ""))
    if not folded:
        return None
    if folded in {"roll", "pouce", "inch", "inches", "longueur", "au pouce", "par pouce"}:
        return "roll"
    if folded in {"case", "caisse", "carton", "pack"}:
        return "case"
    if folded in {"piece", "simple", "unite", "u"}:
        return "piece"
    return None


def _category_name(raw: object, known: list[str]) -> str:
    name = str(raw or "").strip()
    if not name:
        return "Autre"
    folded = _fold(name)
    for existing in known:
        if existing and _fold(existing) == folded:
            return existing[:80]
    return name[:80]


def _unit(value: object) -> str:
    folded = _fold(str(value or ""))
    if folded in {"kg", "kilo", "kilos", "kilogramme", "kilogrammes"}:
        return "kg"
    if folded in {"l", "litre", "litres"}:
        return "L"
    if folded in {"paquet", "paquets", "sachet", "sachets"}:
        return "paquet"
    return "u"


def _discount(value: object) -> int | None:
    if value in ("", None):
        return 0
    parsed = _whole(value)
    if parsed is None:
        return None
    return min(100, max(0, parsed))


def _known_categories(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return []
    names: list[str] = []
    for row in raw[:40]:
        text = str(row or "").strip()
        if text and text not in names:
            names.append(text[:80])
    return names


def _prepare_json_text(text: str) -> str:
    text = text.replace("\ufeff", "").strip()
    fenced = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if fenced:
        text = fenced.group(1).strip()
    elif text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text).strip()
    return (
        text.replace("\u201c", '"')
        .replace("\u201d", '"')
        .replace("\u2018", "'")
        .replace("\u2019", "'")
    )


def _strip_trailing_commas(text: str) -> str:
    out: list[str] = []
    in_string = False
    escape = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if char == ",":
            look = index + 1
            while look < len(text) and text[look] in " \n\r\t":
                look += 1
            if look < len(text) and text[look] in "}]":
                index += 1
                continue
        out.append(char)
        index += 1
    return "".join(out)


def _as_catalog(data: object) -> dict[str, Any] | None:
    if isinstance(data, dict):
        return data
    if isinstance(data, list):
        rows = [row for row in data if isinstance(row, dict)]
        if rows:
            return {"categories": rows}
    return None


def _parse_catalog(text: str) -> dict[str, Any] | None:
    cleaned = _strip_trailing_commas(text.strip())
    if not cleaned:
        return None
    try:
        return _as_catalog(json.loads(cleaned))
    except json.JSONDecodeError:
        pass
    start = cleaned.find("{")
    if start < 0:
        start = cleaned.find("[")
    if start < 0:
        return None
    try:
        data, _ = json.JSONDecoder().raw_decode(cleaned[start:])
    except json.JSONDecodeError:
        return None
    return _as_catalog(data)


def _safe_ends(text: str) -> list[int]:
    """Indexes just after each complete object or array that is still nested."""
    in_string = False
    escape = False
    stack: list[str] = []
    ends: list[int] = []
    for index, char in enumerate(text):
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            continue
        if char in "{[":
            stack.append(char)
            continue
        if char == "}":
            if not stack or stack[-1] != "{":
                break
            stack.pop()
        elif char == "]":
            if not stack or stack[-1] != "[":
                break
            stack.pop()
        else:
            continue
        if stack:
            ends.append(index + 1)
    return ends


def _close_json(text: str) -> str:
    in_string = False
    escape = False
    stack: list[str] = []
    for char in text:
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            continue
        if char in "{[":
            stack.append(char)
        elif char == "}" and stack and stack[-1] == "{":
            stack.pop()
        elif char == "]" and stack and stack[-1] == "[":
            stack.pop()
    if in_string:
        text += '"'
    text = text.rstrip().rstrip(",")
    text += "".join("}" if bracket == "{" else "]" for bracket in reversed(stack))
    return text


def _extract_json(text: str) -> dict[str, Any]:
    prepared = _prepare_json_text(text)
    parsed = _parse_catalog(prepared)
    if parsed is not None:
        return parsed
    start = prepared.find("{")
    if start < 0:
        start = prepared.find("[")
    if start < 0:
        raise CatalogImportError("La réponse de l'assistant n'est pas lisible.")
    body = prepared[start:]
    ends = _safe_ends(body)
    # Prefer the longest closed prefix. Step back if that prefix is still invalid.
    for end in reversed(ends[-40:]):
        candidate = _parse_catalog(_close_json(body[:end]))
        if candidate is not None and candidate.get("categories"):
            candidate["_salvaged"] = True
            return candidate
    for end in reversed(ends[-40:]):
        candidate = _parse_catalog(_close_json(body[:end]))
        if candidate is not None:
            candidate["_salvaged"] = True
            return candidate
    closed = _parse_catalog(_close_json(body))
    if closed is not None:
        closed["_salvaged"] = True
        return closed
    raise CatalogImportError("La réponse de l'assistant n'est pas lisible.")


def _text_chunks(text: str, *, lines: int = 30, chars: int = 4500) -> list[str]:
    """Split a table so each assistant call stays small enough to answer in full."""
    rows = text.splitlines()
    if len(rows) <= lines and len(text) <= chars:
        return [text]
    header = rows[0] if rows else ""
    rest = rows[1:]
    chunks: list[str] = []
    bucket: list[str] = []
    size = len(header) + 1

    def flush() -> None:
        nonlocal bucket, size
        if not bucket and not header:
            return
        body = "\n".join(bucket)
        chunks.append(f"{header}\n{body}".strip() if header else body)
        bucket = []
        size = len(header) + 1

    for row in rest:
        extra = len(row) + 1
        if bucket and (len(bucket) >= lines or size + extra > chars):
            flush()
        bucket.append(row)
        size += extra
        if len(bucket) >= lines or size > chars:
            flush()
    if bucket or (header and not chunks):
        flush()
    return chunks or [text]


def normalize_draft(
    raw: dict[str, Any],
    *,
    usd_rate: int,
    currency_mode: str,
    known_categories: list[str] | None = None,
) -> tuple[dict, list]:
    """Turn the model JSON into products the register can review."""
    known = [name for name in (known_categories or []) if str(name).strip()]
    report = [row for row in (raw.get("report") or []) if isinstance(row, dict)]
    if currency_mode == "usd" and usd_rate > 0:
        report.insert(0, {
            "severity": "info",
            "message": f"Prix lus en dollars, convertis à {usd_rate} HTG pour 1 USD.",
            "item_name": "",
        })
    categories: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for cat in raw.get("categories") or []:
        if not isinstance(cat, dict):
            continue
        name = _category_name(cat.get("name"), known)
        items_out = []
        for item in cat.get("items") or []:
            if not isinstance(item, dict):
                continue
            item_name = str(item.get("name") or "").strip()
            if not item_name:
                continue
            key = (_norm(name), _norm(item_name))
            if key in seen:
                report.append({
                    "severity": "info",
                    "message": f"« {item_name} » apparaît deux fois. Une seule ligne est gardée.",
                    "item_name": item_name,
                })
                continue
            seen.add(key)
            price = _int_amount(item.get("price_htg"))
            if price <= 0:
                report.append({
                    "severity": "warning",
                    "message": f"Prix manquant pour « {item_name} ».",
                    "item_name": item_name,
                })
            stock = item.get("stock")
            if stock in ("", None):
                stock_out = None
            else:
                try:
                    stock_out = max(0, int(stock))
                except (TypeError, ValueError):
                    stock_out = None
                    report.append({
                        "severity": "warning",
                        "message": f"Quantité illisible pour « {item_name} ».",
                        "item_name": item_name,
                    })
            groups = []
            for group in item.get("option_groups") or []:
                if not isinstance(group, dict):
                    continue
                choices = []
                for choice in group.get("choices") or []:
                    if not isinstance(choice, dict):
                        continue
                    choice_name = str(choice.get("name") or "").strip()
                    if choice_name:
                        choices.append({
                            "name": choice_name[:80],
                            "price_delta_htg": _int_amount(choice.get("price_delta_htg")),
                        })
                if not choices:
                    continue
                kind = str(group.get("kind") or "other").lower()
                if kind not in _KINDS:
                    kind = "other"
                groups.append({
                    "name": str(group.get("name") or "Options").strip()[:80] or "Options",
                    "kind": kind,
                    "required": bool(group.get("required")),
                    "multiple": bool(group.get("multiple")),
                    "choices": choices[:20],
                })
            roll_price = _int_amount(item.get("roll_price_htg"))
            roll_width = _whole(item.get("roll_width")) or 0
            min_width = _whole(item.get("min_width"))
            case_price = _int_amount(item.get("case_price_htg"))
            units_per_case = _whole(item.get("units_per_case")) or 0
            if roll_width < 0:
                roll_width = 0
            if units_per_case < 0:
                units_per_case = 0
            explicit = _explicit_sale_mode(item.get("sale_mode"))
            rollish = roll_price > 0 and roll_width >= 1
            caseish = case_price > 0 and units_per_case >= 2
            if explicit in ("roll", "case"):
                mode = explicit
            elif rollish and not caseish:
                mode = "roll"
            elif caseish and not rollish:
                mode = "case"
            else:
                mode = "piece"
            if mode == "roll":
                if min_width is None or min_width < 1:
                    min_width = 1 if roll_width >= 1 else 0
                elif roll_width >= 1 and min_width > roll_width:
                    report.append({
                        "severity": "warning",
                        "message": f"Le minimum dépasse la longueur entière pour « {item_name} ».",
                        "item_name": item_name,
                    })
                    min_width = roll_width
                if roll_price <= 0:
                    report.append({
                        "severity": "warning",
                        "message": f"Prix de la longueur entière manquant pour « {item_name} ».",
                        "item_name": item_name,
                    })
                if roll_width < 1:
                    report.append({
                        "severity": "warning",
                        "message": f"Longueur entière manquante pour « {item_name} ».",
                        "item_name": item_name,
                    })
                case_price = 0
                units_per_case = 0
            elif mode == "case":
                if case_price <= 0:
                    report.append({
                        "severity": "warning",
                        "message": f"Prix de la caisse manquant pour « {item_name} ».",
                        "item_name": item_name,
                    })
                if units_per_case < 2:
                    report.append({
                        "severity": "warning",
                        "message": f"Unités dans la caisse manquantes pour « {item_name} ».",
                        "item_name": item_name,
                    })
                roll_price = 0
                roll_width = 0
                min_width = 0
            else:
                roll_price = 0
                roll_width = 0
                min_width = 0
                case_price = 0
                units_per_case = 0
            discount = _discount(item.get("discount_percent"))
            if discount is None:
                discount = 0
                report.append({
                    "severity": "warning",
                    "message": f"Rabais illisible pour « {item_name} ».",
                    "item_name": item_name,
                })
            items_out.append({
                "name": item_name[:120],
                "sale_mode": mode,
                "price_htg": price,
                "roll_price_htg": roll_price,
                "roll_width": roll_width,
                "min_width": min_width or 0,
                "case_price_htg": case_price,
                "units_per_case": units_per_case,
                "cost_htg": _int_amount(item.get("cost_htg")),
                "barcode": re.sub(r"\s+", "", str(item.get("barcode") or ""))[:40],
                "unit": _unit(item.get("unit")),
                "stock": stock_out,
                "discount_percent": discount,
                "description": str(item.get("description") or "").strip()[:600],
                "option_groups": groups[:6],
            })
        if items_out:
            categories.append({"name": name[:80], "items": items_out})
    if not categories and not any(row.get("severity") == "error" for row in report):
        report.append({
            "severity": "error",
            "message": "Aucun produit détecté. Vérifiez le document ou ajoutez une note.",
            "item_name": "",
        })
    return {"categories": categories}, report


def _cut_at_line(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text.rfind("\n", 0, limit)
    if cut < limit // 2:
        cut = limit
    return text[:cut]


def _suffix(name: str) -> str:
    base = name.rsplit("/", 1)[-1].rsplit("\\", 1)[-1]
    if "." not in base:
        return ""
    return "." + base.rsplit(".", 1)[-1].lower()


def _xml_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _plain_text(name: str, data: bytes, limit: int = 40000) -> str:
    for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = data.decode("latin-1", errors="replace")
    text = text.replace("\x00", "").strip()
    if not text:
        raise CatalogImportError(f"« {name} » est vide.")
    return text[:limit]


def _xlsx_text(name: str, data: bytes) -> str:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise CatalogImportError(f"« {name} » n'est pas un classeur Excel lisible.") from exc
    strings: list[str] = []
    if "xl/sharedStrings.xml" in archive.namelist():
        root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        for node in root.iter():
            if _xml_name(node.tag) != "si":
                continue
            strings.append("".join(
                child.text or ""
                for child in node.iter()
                if _xml_name(child.tag) == "t"
            ))
    sheets = sorted(
        path for path in archive.namelist()
        if path.startswith("xl/worksheets/sheet") and path.endswith(".xml")
    )
    blocks: list[str] = []
    for sheet in sheets:
        root = ET.fromstring(archive.read(sheet))
        lines: list[str] = []
        for row in root.iter():
            if _xml_name(row.tag) != "row":
                continue
            cells: list[str] = []
            for cell in list(row):
                if _xml_name(cell.tag) != "c":
                    continue
                value = ""
                for child in list(cell):
                    local = _xml_name(child.tag)
                    if local == "v" and child.text:
                        value = child.text
                    elif local == "is":
                        value = "".join(
                            part.text or ""
                            for part in child.iter()
                            if _xml_name(part.tag) == "t"
                        )
                if cell.attrib.get("t") == "s" and value.isdigit():
                    index = int(value)
                    value = strings[index] if index < len(strings) else ""
                cells.append(value.strip())
            if any(cells):
                lines.append("\t".join(cells))
        if lines:
            blocks.append("\n".join(lines))
    text = "\n\n".join(blocks).strip()
    if not text:
        raise CatalogImportError(f"« {name} » ne contient aucune ligne.")
    return _cut_at_line(text, 120000)


def _docx_text(name: str, data: bytes) -> str:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise CatalogImportError(f"« {name} » n'est pas un document Word lisible.") from exc
    if "word/document.xml" not in archive.namelist():
        raise CatalogImportError(f"« {name} » n'est pas un document Word lisible.")
    root = ET.fromstring(archive.read("word/document.xml"))
    lines: list[str] = []
    for paragraph in root.iter():
        if _xml_name(paragraph.tag) != "p":
            continue
        text = "".join(
            node.text or ""
            for node in paragraph.iter()
            if _xml_name(node.tag) == "t"
        ).strip()
        if text:
            lines.append(text)
    if not lines:
        raise CatalogImportError(f"« {name} » ne contient aucun texte.")
    return "\n".join(lines)[:40000]


def _ods_text(name: str, data: bytes) -> str:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise CatalogImportError(f"« {name} » n'est pas un tableur lisible.") from exc
    if "content.xml" not in archive.namelist():
        raise CatalogImportError(f"« {name} » n'est pas un tableur lisible.")
    root = ET.fromstring(archive.read("content.xml"))
    lines: list[str] = []
    for row in root.iter():
        if _xml_name(row.tag) != "table-row":
            continue
        cells: list[str] = []
        for cell in list(row):
            if _xml_name(cell.tag) != "table-cell":
                continue
            value = " ".join(
                (node.text or "").strip()
                for node in cell.iter()
                if _xml_name(node.tag) == "p" and (node.text or "").strip()
            )
            cells.append(value)
        if any(cells):
            lines.append("\t".join(cells).strip())
    text = "\n".join(lines).strip()
    if not text:
        raise CatalogImportError(f"« {name} » ne contient aucune ligne.")
    return text[:40000]


def _odt_text(name: str, data: bytes) -> str:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise CatalogImportError(f"« {name} » n'est pas un document lisible.") from exc
    if "content.xml" not in archive.namelist():
        raise CatalogImportError(f"« {name} » n'est pas un document lisible.")
    root = ET.fromstring(archive.read("content.xml"))
    lines = [
        "".join(node.itertext()).strip()
        for node in root.iter()
        if _xml_name(node.tag) in {"p", "h"}
    ]
    text = "\n".join(line for line in lines if line).strip()
    if not text:
        raise CatalogImportError(f"« {name} » ne contient aucun texte.")
    return text[:40000]


def _legacy_office_text(name: str, data: bytes) -> str:
    """Old .xls and .doc files: keep the readable words embedded in the file."""
    pieces: list[str] = []
    run: list[str] = []
    for byte in data:
        if 32 <= byte < 127 or byte in (9, 10, 13):
            run.append(chr(byte))
        elif len(run) >= 4:
            pieces.append("".join(run))
            run = []
        else:
            run = []
    if len(run) >= 4:
        pieces.append("".join(run))
    wide = data.decode("utf-16le", errors="ignore")
    pieces.extend(re.findall(r"[0-9A-Za-zÀ-ÿ][0-9A-Za-zÀ-ÿ .,&%/+\-]{2,}", wide))
    text = "\n".join(dict.fromkeys(piece.strip() for piece in pieces if piece.strip()))
    if len(text) < 8:
        kind = "Excel" if name.lower().endswith(".xls") else "Word"
        raise CatalogImportError(
            f"« {name} » est un ancien fichier {kind}. "
            "Enregistrez-le en .xlsx, .csv ou .docx, puis réessayez."
        )
    return text[:40000]


def _file_block(name: str, mime: str, data: bytes) -> dict[str, Any]:
    encoded = base64.standard_b64encode(data).decode("ascii")
    suffix = _suffix(name)
    if mime.startswith("image/") or suffix in {".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic"}:
        media = mime if mime.startswith("image/") else "image/jpeg"
        return {"type": "image", "source": {"type": "base64", "media_type": media, "data": encoded}}
    if mime == "application/pdf" or suffix == ".pdf":
        return {
            "type": "document",
            "source": {"type": "base64", "media_type": "application/pdf", "data": encoded},
        }
    if suffix in {".xlsx", ".xlsm"}:
        text = _xlsx_text(name, data)
    elif suffix == ".docx":
        text = _docx_text(name, data)
    elif suffix == ".ods":
        text = _ods_text(name, data)
    elif suffix == ".odt":
        text = _odt_text(name, data)
    elif suffix in {".xls", ".doc"}:
        text = _legacy_office_text(name, data)
    elif suffix in {".csv", ".tsv", ".txt", ".md", ".json"} or mime.startswith("text/"):
        text = _plain_text(name, data)
    elif b"\x00" not in data[:800]:
        text = _plain_text(name, data)
    else:
        raise CatalogImportError(
            f"« {name} » : utilisez Excel (.xlsx), CSV, Word (.docx), PDF ou une photo."
        )
    return {"type": "text", "text": f"--- {name} ---\n{text}"}


def _call_claude(content: list[dict[str, Any]]) -> dict[str, Any]:
    key = _api_key()
    if not key:
        raise CatalogImportError("L'assistant IA n'est pas configuré sur le serveur.")
    body = json.dumps({
        "model": _model(),
        "max_tokens": MAX_TOKENS,
        "temperature": 0,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": content}],
    }).encode()
    request = urllib.request.Request(
        ANTHROPIC_URL,
        data=body,
        headers={
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
            "anthropic-beta": "pdfs-2024-09-25",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            payload = json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:300]
        raise CatalogImportError(f"L'assistant a répondu {exc.code}. {detail}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise CatalogImportError("L'assistant n'a pas répondu. Réessayez.") from exc
    parts = [
        block.get("text") or ""
        for block in (payload.get("content") or [])
        if isinstance(block, dict) and block.get("type") == "text"
    ]
    text = "\n".join(parts)
    if not text.strip():
        raise CatalogImportError("L'assistant a renvoyé une réponse vide.")
    try:
        return _extract_json(text)
    except CatalogImportError:
        stop = payload.get("stop_reason") or ""
        print(
            f"catalog-import unreadable stop={stop} chars={len(text)}",
            flush=True,
        )
        raise


def _decode_files(raw_files: object) -> list[tuple[str, str, bytes]]:
    if not isinstance(raw_files, list) or not raw_files:
        raise CatalogImportError("Ajoutez au moins un document.")
    if len(raw_files) > MAX_FILES:
        raise CatalogImportError(f"Maximum {MAX_FILES} fichiers.")
    files = []
    for raw in raw_files:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or "document").strip()[:120] or "document"
        mime = str(raw.get("content_type") or "application/octet-stream")
        try:
            data = base64.b64decode(str(raw.get("data_base64") or ""), validate=False)
        except (ValueError, TypeError) as exc:
            raise CatalogImportError(f"Impossible de lire « {name} ».") from exc
        if not data:
            raise CatalogImportError(f"« {name} » est vide.")
        if len(data) > MAX_FILE_BYTES:
            raise CatalogImportError(f"« {name} » dépasse 4 Mo.")
        files.append((name, mime, data))
    if not files:
        raise CatalogImportError("Ajoutez au moins un document.")
    return files


def _known_line(known: list[str]) -> str:
    if not known:
        return (
            "Ce magasin n'a encore aucune catégorie. "
            "Garde le rayon écrit dans le document. "
            "S'il n'y en a pas, utilise Autre.\n"
        )
    shown = ", ".join(known[:40])
    return (
        f"Catégories déjà utilisées par ce magasin : {shown}.\n"
        "Si le rayon du document correspond à l'une d'elles, reprends son orthographe. "
        "Sinon garde le nom du document : il devient une catégorie de ce magasin seulement.\n"
    )


def _content_parts(name: str, mime: str, data: bytes) -> list[dict[str, Any]]:
    block = _file_block(name, mime, data)
    if block.get("type") != "text":
        return [block]
    text = str(block.get("text") or "")
    prefix = ""
    body = text
    if text.startswith("--- "):
        prefix, _, body = text.partition("\n")
        prefix = prefix + "\n"
    chunks = _text_chunks(body)
    if len(chunks) == 1:
        return [block]
    total = len(chunks)
    return [
        {
            "type": "text",
            "text": (
                f"{prefix}{chunk}\n\n"
                f"Partie {index}/{total} du document. "
                "Extrais seulement les produits de cette partie."
            ),
        }
        for index, chunk in enumerate(chunks, start=1)
    ]


def extract_catalog(
    files: list[tuple[str, str, bytes]],
    *,
    owner_note: str,
    currency_mode: str,
    usd_rate: int,
    known_categories: list[str] | None = None,
    on_progress=None,
) -> tuple[dict, list]:
    known = [name for name in (known_categories or []) if str(name).strip()]
    categories: list[dict] = []
    report: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for index, (name, mime, data) in enumerate(files, start=1):
        note = owner_note.strip()
        parts = _content_parts(name, mime, data)
        for part_index, block in enumerate(parts, start=1):
            if on_progress is not None:
                if len(parts) == 1:
                    on_progress("Lecture du document…")
                else:
                    on_progress(f"Partie {part_index}/{len(parts)}…")
            intro = (
                f"Document {index}/{len(files)} : {name}.\n"
                f"Devise indiquée par le commerçant : {currency_mode}.\n"
                f"Taux : 1 USD = {usd_rate or 0} HTG.\n"
                f"{_known_line(known)}"
            )
            if len(parts) > 1:
                intro += f"Partie {part_index}/{len(parts)}.\n"
            if note:
                intro += f"Note du commerçant : {note}\n"
            try:
                raw = _call_claude([
                    {"type": "text", "text": intro},
                    block,
                ])
            except CatalogImportError:
                if len(parts) == 1:
                    raise
                report.append({
                    "severity": "warning",
                    "message": (
                        f"Partie {part_index}/{len(parts)} de « {name} » illisible. "
                        "Les produits des autres parties sont gardés."
                    ),
                    "item_name": "",
                })
                continue
            salvaged = bool(raw.pop("_salvaged", False)) if isinstance(raw, dict) else False
            draft, part_report = normalize_draft(
                raw,
                usd_rate=usd_rate,
                currency_mode=currency_mode,
                known_categories=known,
            )
            if salvaged:
                report.append({
                    "severity": "info",
                    "message": "La fin d'une réponse était incomplète. Les produits complets sont gardés.",
                    "item_name": "",
                })
            count = sum(len(cat["items"]) for cat in draft["categories"])
            if len(parts) == 1:
                report.append({
                    "severity": "info",
                    "message": f"Document « {name} » : {count} produit(s).",
                    "item_name": "",
                })
            report.extend(part_report)
            for cat in draft["categories"]:
                bucket = next((row for row in categories if _norm(row["name"]) == _norm(cat["name"])), None)
                if bucket is None:
                    bucket = {"name": cat["name"], "items": []}
                    categories.append(bucket)
                for item in cat["items"]:
                    key = (_norm(cat["name"]), _norm(item["name"]))
                    if key in seen:
                        continue
                    seen.add(key)
                    bucket["items"].append(item)
        if len(parts) > 1:
            report.append({
                "severity": "info",
                "message": f"Document « {name} » lu en {len(parts)} parties.",
                "item_name": "",
            })
    if not categories:
        report.append({
            "severity": "error",
            "message": "Aucun produit détecté. Vérifiez le document ou ajoutez une note.",
            "item_name": "",
        })
    return {"categories": categories}, report


class CatalogJobs:
    def __init__(self) -> None:
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()

    def start(self, body: dict) -> dict:
        currency = str(body.get("currency_mode") or "htg").lower()
        if currency not in ("htg", "usd", "mixed"):
            raise CatalogImportError("Choisissez HTG, USD ou mixte.")
        try:
            rate = int(float(body.get("usd_rate") or 0))
        except (TypeError, ValueError) as exc:
            raise CatalogImportError("Taux USD invalide.") from exc
        if currency in ("usd", "mixed") and rate <= 0:
            raise CatalogImportError("Indiquez combien de gourdes valent 1 dollar.")
        files = _decode_files(body.get("files"))
        note = str(body.get("owner_note") or "")[:2000]
        known = _known_categories(body.get("known_categories"))
        job_id = secrets.token_urlsafe(12)
        job = {
            "id": job_id,
            "status": "running",
            "progress": "Lecture du document…",
            "error": "",
            "draft": {},
            "report": [],
            "created_at": int(time.time()),
        }
        with self._lock:
            self._jobs[job_id] = job
            self._prune()
        threading.Thread(
            target=self._run,
            args=(job_id, files, note, currency, rate, known),
            name=f"catalog-import-{job_id}",
            daemon=True,
        ).start()
        return {"id": job_id, "status": "running"}

    def get(self, job_id: str) -> dict:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                raise CatalogImportError("Cette analyse n'existe plus.", status=404)
            return dict(job)

    def _run(
        self,
        job_id: str,
        files,
        note: str,
        currency: str,
        rate: int,
        known: list[str],
    ) -> None:
        def on_progress(message: str) -> None:
            with self._lock:
                job = self._jobs.get(job_id)
                if job and job.get("status") == "running":
                    job["progress"] = message

        try:
            draft, report = extract_catalog(
                files,
                owner_note=note,
                currency_mode=currency,
                usd_rate=rate,
                known_categories=known,
                on_progress=on_progress,
            )
            self._finish(job_id, status="succeeded", draft=draft, report=report, progress="Terminé.")
        except CatalogImportError as exc:
            self._finish(job_id, status="failed", error=exc.message, progress="Échec.")
        except Exception:
            import traceback
            traceback.print_exc()
            self._finish(job_id, status="failed", error="L'analyse a échoué. Réessayez.", progress="Échec.")

    def _finish(self, job_id: str, **fields: object) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return
            job.update(fields)

    def _prune(self) -> None:
        if len(self._jobs) <= 40:
            return
        stale = sorted(self._jobs, key=lambda key: self._jobs[key].get("created_at", 0))
        for key in stale[: len(self._jobs) - 40]:
            self._jobs.pop(key, None)


JOBS = CatalogJobs()

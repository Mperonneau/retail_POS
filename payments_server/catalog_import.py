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
          "price_htg": 0,
          "price_source": "HTG|USD",
          "cost_htg": 0,
          "barcode": "",
          "unit": "u",
          "stock": null,
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
- price_htg et price_delta_htg et cost_htg sont des montants en GOURDES entières.
- Si un prix est en USD, convertis-le en HTG avec le taux fourni (arrondi à l'entier) et mets price_source à USD.
- cost_htg reste 0 si le document ne donne pas de prix d'achat.
- barcode reprend le code-barres ou la référence imprimée, sinon "".
- unit : u, kg, L, paquet, ou l'unité écrite. Défaut u.
- stock : quantité entière si le document la donne, sinon null. N'invente pas un stock.
- Regroupe par rayon du magasin (Alimentation, Boissons, Ménage, Hygiène, Électronique, Papeterie, Autre).
- Tailles ou conditionnements → kind "size". Couleurs → "color". Suppléments payants → "extra". Le reste → "other".
- Ignore adresse, téléphone, slogans, totaux de facture et lignes qui ne sont pas des produits.
- Signale dans report : prix manquants, conversion USD, doublons, quantité illisible.
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


def _int_amount(value: object) -> int:
    try:
        return max(0, int(round(float(value or 0))))
    except (TypeError, ValueError):
        return 0


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            data = json.loads(match.group(0))
            if isinstance(data, dict):
                return data
        except json.JSONDecodeError:
            pass
    start = text.find("{")
    if start < 0:
        raise CatalogImportError("La réponse de l'assistant n'est pas lisible.")
    chunk = text[start:].rstrip().rstrip(",")
    chunk += "]" * (chunk.count("[") - chunk.count("]"))
    chunk += "}" * (chunk.count("{") - chunk.count("}"))
    try:
        data = json.loads(chunk)
    except json.JSONDecodeError as exc:
        raise CatalogImportError("La réponse de l'assistant n'est pas lisible.") from exc
    if not isinstance(data, dict):
        raise CatalogImportError("La réponse de l'assistant n'est pas lisible.")
    return data


def normalize_draft(raw: dict[str, Any], *, usd_rate: int, currency_mode: str) -> tuple[dict, list]:
    """Turn the model JSON into products the register can review."""
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
        name = str(cat.get("name") or "").strip() or "Autre"
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
            unit = str(item.get("unit") or "u").strip()[:12] or "u"
            items_out.append({
                "name": item_name[:120],
                "price_htg": price,
                "cost_htg": _int_amount(item.get("cost_htg")),
                "barcode": re.sub(r"\s+", "", str(item.get("barcode") or ""))[:40],
                "unit": unit,
                "stock": stock_out,
                "description": str(item.get("description") or "").strip()[:300],
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
    return text[:40000]


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
    if not "".join(parts).strip():
        raise CatalogImportError("L'assistant a renvoyé une réponse vide.")
    return _extract_json("\n".join(parts))


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


def extract_catalog(
    files: list[tuple[str, str, bytes]],
    *,
    owner_note: str,
    currency_mode: str,
    usd_rate: int,
) -> tuple[dict, list]:
    categories: list[dict] = []
    report: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for index, (name, mime, data) in enumerate(files, start=1):
        note = owner_note.strip()
        intro = (
            f"Document {index}/{len(files)} : {name}.\n"
            f"Devise indiquée par le commerçant : {currency_mode}.\n"
            f"Taux : 1 USD = {usd_rate or 0} HTG.\n"
        )
        if note:
            intro += f"Note du commerçant : {note}\n"
        raw = _call_claude([
            {"type": "text", "text": intro},
            _file_block(name, mime, data),
        ])
        draft, part_report = normalize_draft(raw, usd_rate=usd_rate, currency_mode=currency_mode)
        count = sum(len(cat["items"]) for cat in draft["categories"])
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
            args=(job_id, files, note, currency, rate),
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

    def _run(self, job_id: str, files, note: str, currency: str, rate: int) -> None:
        try:
            draft, report = extract_catalog(
                files, owner_note=note, currency_mode=currency, usd_rate=rate,
            )
            self._finish(job_id, status="succeeded", draft=draft, report=report, progress="Terminé.")
        except CatalogImportError as exc:
            self._finish(job_id, status="failed", error=exc.message, progress="Échec.")
        except Exception:
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

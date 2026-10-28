"""Serves the vitrine and the link-preview tags for each shop.

Facebook and Instagram request the shop URL and read the HTML. They never
run Flutter, so a shop path is the app plus that shop's name, text and photo.
"""

from __future__ import annotations

import html
import json
import mimetypes
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from og_page import (
    MIN_IMAGE,
    cover_url,
    image_dimensions,
    inject_preview,
    preview_card,
    shop_blurb,
    shop_slug,
)

def _web_root() -> Path:
    raw = os.environ.get("WEB_ROOT")
    path = Path(raw) if raw else Path(__file__).resolve().parent / "build" / "web"
    if not path.is_absolute():
        path = Path.cwd() / path
    return path.resolve()


WEB_ROOT = _web_root()
API_BASE = (os.environ.get("STOREFRONT_API") or "https://retail-pos-payments.onrender.com").rstrip("/")
# Where this process is reached. Preview photos and the app's files live here.
SERVICE_ORIGIN = (os.environ.get("RENDER_EXTERNAL_URL") or "").rstrip("/")
# The link people share, when a rewrite keeps that address in the browser.
PUBLIC_BASE = (os.environ.get("PUBLIC_BASE") or "").rstrip("/")
PORT = int(os.environ.get("PORT") or "8788")

_INDEX = (WEB_ROOT / "index.html").read_text(encoding="utf-8") if (WEB_ROOT / "index.html").is_file() else (
    "<!doctype html><html><head><title>Vitrine</title></head><body></body></html>"
)
_cache: dict[str, tuple[float, dict | None]] = {}
_cache_lock = threading.Lock()
_cards: dict[str, bytes] = {}


def fetch_shop(slug: str) -> dict | None:
    now = time.time()
    with _cache_lock:
        cached = _cache.get(slug)
        if cached and now - cached[0] < 30:
            return cached[1]
    shop: dict | None = None
    try:
        request = urllib.request.Request(
            f"{API_BASE}/storefront/shops/{slug}",
            headers={"Accept": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            parsed = json.loads(response.read().decode() or "{}")
            if isinstance(parsed, dict) and parsed.get("name"):
                shop = parsed
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        shop = None
    with _cache_lock:
        _cache[slug] = (now, shop)
    return shop


def image_size(url: str) -> tuple[int, int] | None:
    """Pixel size when the photo is large enough for Facebook to display it."""
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "VitrinePreview"})
        with urllib.request.urlopen(request, timeout=8) as response:
            data = response.read(262144)
    except (OSError, urllib.error.URLError, TimeoutError):
        return None
    size = image_dimensions(data)
    if size is None:
        return None
    width, height = size
    if width < MIN_IMAGE or height < MIN_IMAGE:
        return None
    return size


def _origin(host: str) -> str:
    return SERVICE_ORIGIN or f"https://{host}".rstrip("/")


def _with_base(page: str, origin: str) -> str:
    """Load the app's files from the same build that produced this HTML."""
    tag = f'<base href="{html.escape(origin.rstrip("/") + "/", quote=True)}">'
    lower = page.lower()
    start = lower.find("<base ")
    if start >= 0:
        end = page.find(">", start)
        return page[:start] + tag + page[end + 1 :]
    head = lower.find("<head>")
    if head >= 0:
        return page[: head + len("<head>")] + "\n  " + tag + page[head + len("<head>") :]
    return tag + page


def page_for(path: str, host: str) -> bytes:
    origin = _origin(host)
    public = PUBLIC_BASE or origin
    slug = shop_slug(path)
    title = "Vitrine"
    description = "Commandez en ligne et payez par carte ou MonCash."
    image = ""
    width = 0
    height = 0
    image_type = ""
    page_url = public + (path if path.startswith("/") else "/" + path)
    if slug:
        shop = fetch_shop(slug)
        if shop:
            title = str(shop.get("name") or title)
            description = shop_blurb(shop) or description
            photo = cover_url(shop, API_BASE)
            size = image_size(photo) if photo else None
            if photo and size:
                image = photo
                width, height = size
                image_type = _mime_for(photo)
            else:
                card = _cards.get(slug)
                if card is None:
                    card = preview_card(title, description)
                    if card:
                        _cards[slug] = card
                if card:
                    image = f"{origin}/preview/{slug}.png"
                    width, height = 1200, 630
                    image_type = "image/png"
    html_page = inject_preview(
        _INDEX,
        title=title,
        description=description,
        image=image,
        page_url=page_url.split("?")[0],
        image_width=width,
        image_height=height,
        image_type=image_type,
    )
    return _with_base(html_page, origin).encode()


def _mime_for(url: str) -> str:
    lower = url.lower().split("?", 1)[0]
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith(".webp"):
        return "image/webp"
    if lower.endswith(".jpg") or lower.endswith(".jpeg"):
        return "image/jpeg"
    return "image/jpeg"


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        path = unquote(urlparse(self.path).path)
        if path == "/health":
            raw = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(raw)
            return
        if path.startswith("/preview/") and path.endswith(".png"):
            slug = path[len("/preview/") : -len(".png")].lower()
            if shop_slug("/" + slug) != slug:
                self.send_error(404)
                return
            card = _cards.get(slug) or b""
            if not card:
                shop = fetch_shop(slug) or {}
                card = preview_card(str(shop.get("name") or slug), shop_blurb(shop))
                if card:
                    _cards[slug] = card
            if not card:
                self.send_error(404)
                return
            self._send(200, card, "image/png", "public, max-age=300")
            return
        file_path = _safe_file(path)
        if file_path is not None:
            mime = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
            self._send(200, file_path.read_bytes(), mime, "public, max-age=3600")
            return
        if "." in path.rsplit("/", 1)[-1]:
            self.send_error(404)
            return
        host = (self.headers.get("Host") or "localhost").split(":")[0]
        self._send(200, page_for(path, host), "text/html; charset=utf-8", "no-cache")

    def _send(self, status: int, body: bytes, mime: str, cache: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        print("%s %s" % (self.command, self.path))


def _safe_file(path: str) -> Path | None:
    if path in ("", "/"):
        return None
    relative = path.lstrip("/")
    candidate = (WEB_ROOT / relative).resolve()
    root = WEB_ROOT.resolve()
    if root not in candidate.parents and candidate != root:
        return None
    if candidate.is_file():
        return candidate
    return None


def main() -> None:
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()

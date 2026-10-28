"""Open Graph tags for a shop page.

Facebook and Instagram read these from the first HTML response. They do not
run the Flutter app, so the tags have to be in the file the link points at.
"""

from __future__ import annotations

import html
import io
from pathlib import Path
from typing import Callable

MIN_IMAGE = 200


def shop_slug(path: str) -> str:
    """A public shop path (`/boutique-soleil`), or empty for app routes."""
    clean = (path or "/").split("?", 1)[0].split("#", 1)[0]
    parts = [part for part in clean.split("/") if part]
    if len(parts) != 1:
        return ""
    slug = parts[0].lower()
    if slug in {
        "orders",
        "favorites",
        "profile",
        "login",
        "cart",
        "about",
        "help",
        "health",
        "assets",
        "icons",
        "canvaskit",
        "r",
    }:
        return ""
    if not (3 <= len(slug) <= 40):
        return ""
    if slug[0] == "-" or slug[-1] == "-" or not all(c.isalnum() or c == "-" for c in slug):
        return ""
    return slug


def absolute_url(base: str, path: str) -> str:
    if not path:
        return ""
    if path.startswith("http://") or path.startswith("https://"):
        return path
    root = (base or "").rstrip("/")
    if not path.startswith("/"):
        path = "/" + path
    return root + path


def shop_blurb(shop: dict) -> str:
    """One line Facebook can show under the shop name."""
    place = ", ".join(
        part for part in (str(shop.get("city") or "").strip(), str(shop.get("department") or "").strip()) if part
    )
    categories = " · ".join(str(name) for name in (shop.get("business_categories") or []) if str(name).strip())
    description = str(shop.get("description") or "").strip()
    availability = shop.get("availability") if isinstance(shop.get("availability"), dict) else {}
    try:
        open_hour = int(availability.get("open_hour", shop.get("open_hour", 8)))
        close_hour = int(availability.get("close_hour", shop.get("close_hour", 18)))
    except (TypeError, ValueError):
        open_hour, close_hour = 8, 18
    hours = f"Ouvert {open_hour}h – {close_hour}h"
    return ". ".join(part for part in (place, categories, description, hours) if part)[:300]


def cover_url(shop: dict, api_base: str, big_enough: Callable[[str], bool] | None = None) -> str:
    """Public photo, when it is large enough for Facebook to display it."""
    raw = str(shop.get("cover_url") or "").strip()
    if not raw:
        products = shop.get("products") or []
        if products and isinstance(products[0], dict):
            raw = str(products[0].get("photo_url") or "").strip()
    url = absolute_url(api_base, raw)
    if not url:
        return ""
    if big_enough is not None and not big_enough(url):
        return ""
    return url


def inject_preview(
    index_html: str,
    *,
    title: str,
    description: str,
    image: str,
    page_url: str,
    image_width: int = 0,
    image_height: int = 0,
    image_type: str = "",
) -> str:
    """Put the shop name, text and photo in the page Facebook scrapes."""
    safe_title = html.escape(" ".join((title or "").split()) or "Vitrine", quote=True)
    safe_description = html.escape(" ".join((description or "").split()), quote=True)
    safe_url = html.escape(page_url.strip(), quote=True)
    safe_image = html.escape(image.strip(), quote=True)
    tags = [
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Vitrine">',
        '<meta property="og:locale" content="fr_FR">',
        f'<meta property="og:title" content="{safe_title}">',
        f'<meta property="og:description" content="{safe_description}">',
        f'<meta property="og:url" content="{safe_url}">',
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{safe_title}">',
        f'<meta name="twitter:description" content="{safe_description}">',
    ]
    if safe_image:
        tags.append(f'<meta property="og:image" content="{safe_image}">')
        if safe_image.startswith("https://"):
            tags.append(f'<meta property="og:image:secure_url" content="{safe_image}">')
        if image_type:
            tags.append(
                f'<meta property="og:image:type" content="{html.escape(image_type, quote=True)}">'
            )
        if image_width >= MIN_IMAGE and image_height >= MIN_IMAGE:
            tags.append(f'<meta property="og:image:width" content="{int(image_width)}">')
            tags.append(f'<meta property="og:image:height" content="{int(image_height)}">')
        tags.append(f'<meta property="og:image:alt" content="{safe_title}">')
        tags.append(f'<meta name="twitter:image" content="{safe_image}">')
    block = "\n  ".join(tags)
    page = index_html
    if "<title>" in page and "</title>" in page:
        start = page.find("<title>")
        end = page.find("</title>", start)
        page = page[:start] + f"<title>{safe_title}</title>" + page[end + len("</title>") :]
    else:
        block = f"<title>{safe_title}</title>\n  " + block
    description_tag = f'<meta name="description" content="{safe_description}">'
    if 'name="description"' in page:
        start = page.find('<meta name="description"')
        end = page.find(">", start)
        page = page[:start] + description_tag + page[end + 1 :]
    marker = "</head>"
    if marker not in page:
        return block + page
    return page.replace(marker, f"  {block}\n{marker}", 1)


def preview_card(title: str, description: str) -> bytes:
    """A 1200×630 picture when the shop has no photo Facebook can use."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return b""
    image = Image.new("RGB", (1200, 630), "#1A5AA8")
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 18, 630), fill="#F5A524")
    font = _font(ImageFont, 64)
    small = _font(ImageFont, 32)
    name = " ".join((title or "Vitrine").split())[:80]
    y = 160
    for line in _lines(name, font, 1040)[:2]:
        draw.text((72, y), line, fill="white", font=font)
        y += 76
    blurb = " ".join((description or "").split())
    y = max(y + 16, 300)
    for line in _lines(blurb, small, 1040):
        if y > 540:
            break
        draw.text((72, y), line, fill="#E8F0F8", font=small)
        y += 46
    out = io.BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def image_dimensions(data: bytes) -> tuple[int, int] | None:
    """Width and height of a PNG or JPEG, when the header is readable."""
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        return (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big"))
    if data.startswith(b"\xff\xd8"):
        return _jpeg_size(data)
    if data.startswith(b"RIFF") and b"WEBP" in data[:16]:
        return _webp_size(data)
    return None


def _jpeg_size(data: bytes) -> tuple[int, int] | None:
    index = 2
    view = data
    while index + 9 < len(view):
        if view[index] != 0xFF:
            index += 1
            continue
        marker = view[index + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3):
            height = int.from_bytes(view[index + 5 : index + 7], "big")
            width = int.from_bytes(view[index + 7 : index + 9], "big")
            return (width, height)
        if marker == 0xD8 or marker == 0xD9:
            index += 2
            continue
        if index + 4 > len(view):
            break
        length = int.from_bytes(view[index + 2 : index + 4], "big")
        if length < 2:
            break
        index += 2 + length
    return None


def _webp_size(data: bytes) -> tuple[int, int] | None:
    if len(data) >= 30 and data[12:16] == b"VP8X":
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return (width, height)
    return None


def _lines(text: str, font, max_px: int) -> list[str]:
    words = text.split()
    if not words:
        return []
    lines: list[str] = []
    line = words[0]
    for word in words[1:]:
        trial = f"{line} {word}"
        width = _text_width(trial, font)
        if width > max_px and line:
            lines.append(line)
            line = word
        else:
            line = trial
    if line:
        lines.append(line)
    return lines


def _text_width(text: str, font) -> float:
    getlength = getattr(font, "getlength", None)
    if getlength is not None:
        try:
            return float(getlength(text))
        except (OSError, TypeError):
            pass
    return float(len(text) * 28)


def _font(image_font, size: int):
    bundled = Path(__file__).resolve().parent / "fonts" / "DejaVuSans.ttf"
    for path in (bundled, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return image_font.truetype(str(path), size)
        except OSError:
            continue
    return image_font.load_default()

"""Image uploads sent as data URLs by the Flutter apps.

Public photos (catalogue, vitrine cover) are content-addressed so the same
image is stored once and can be cached forever. Private images (check scans)
get random names and are only served through authenticated endpoints.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import re
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

from .exceptions import ApiError

DATA_URL_RE = re.compile(r"^data:image/(png|jpeg|jpg|webp);base64,(.+)$", re.DOTALL)
PUBLIC_NAME_RE = re.compile(r"^[a-f0-9]{32}\.(png|jpg|webp)$")
MAX_IMAGE_BYTES = 2_000_000
PUBLIC_DIR = "photos"
PRIVATE_DIR = "private"
MIME = {"png": "image/png", "jpg": "image/jpeg", "webp": "image/webp"}
_MAGIC = {
    "png": (b"\x89PNG\r\n\x1a\n",),
    "jpg": (b"\xff\xd8\xff",),
    "webp": (b"RIFF",),
}


def decode_data_url(data_url: str, *, max_bytes: int = MAX_IMAGE_BYTES) -> tuple[bytes, str] | None:
    match = DATA_URL_RE.match((data_url or "").strip())
    if not match:
        return None
    ext = {"jpeg": "jpg", "jpg": "jpg", "png": "png", "webp": "webp"}[match.group(1)]
    try:
        raw = base64.b64decode(match.group(2), validate=False)
    except (binascii.Error, ValueError):
        return None
    if not raw or len(raw) > max_bytes:
        return None
    if not raw.startswith(_MAGIC[ext]) or (ext == "webp" and raw[8:12] != b"WEBP"):
        return None
    return raw, ext


def save_public_image(data_url: str) -> str:
    """Store a catalogue/cover photo and return its file name ('' when invalid)."""
    decoded = decode_data_url(data_url)
    if decoded is None:
        return ""
    raw, ext = decoded
    name = f"{hashlib.sha256(raw).hexdigest()[:32]}.{ext}"
    path = f"{PUBLIC_DIR}/{name}"
    if not default_storage.exists(path):
        default_storage.save(path, ContentFile(raw))
    return name


def public_image_exists(name: str) -> bool:
    return bool(PUBLIC_NAME_RE.match(name or "")) and default_storage.exists(f"{PUBLIC_DIR}/{name}")


def read_public_image(name: str) -> tuple[bytes, str]:
    if not PUBLIC_NAME_RE.match(name or ""):
        raise ApiError("Photo introuvable.", 404)
    path = f"{PUBLIC_DIR}/{name}"
    if not default_storage.exists(path):
        raise ApiError("Photo introuvable.", 404)
    with default_storage.open(path, "rb") as fh:
        return fh.read(), MIME[name.rsplit(".", 1)[1]]


def public_image_url(name: str) -> str:
    return f"/storefront/photos/{name}" if name else ""


def save_private_image(data_url: str, folder: str, *, max_bytes: int = 4_000_000) -> str:
    decoded = decode_data_url(data_url, max_bytes=max_bytes)
    if decoded is None:
        raise ApiError("Photo illisible. Utilisez une image PNG, JPEG ou WebP de moins de 4 Mo.")
    raw, ext = decoded
    path = f"{PRIVATE_DIR}/{folder}/{uuid.uuid4().hex}.{ext}"
    return default_storage.save(path, ContentFile(raw))


def read_private_image(path: str) -> tuple[bytes, str]:
    if not path or not path.startswith(f"{PRIVATE_DIR}/") or ".." in path:
        raise ApiError("Photo introuvable.", 404)
    if not default_storage.exists(path):
        raise ApiError("Photo introuvable.", 404)
    with default_storage.open(path, "rb") as fh:
        return fh.read(), MIME.get(path.rsplit(".", 1)[-1], "application/octet-stream")

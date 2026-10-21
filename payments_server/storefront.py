"""Retail storefront (vitrine) store.

The retail POS publishes its vitrine settings and catalog here with a per-shop
secret key. Visitors browse the public catalog, then submit a devis or a
commande. Every request gets an unguessable link that anyone can open and pay
(card in USD with fees, or MonCash in HTG). The POS pulls its inbox to import
devis and paid orders.

Prices are always recomputed here from the published catalog; client totals
are never trusted. Payment providers are called from server.py; this module
only records what they confirmed.

Storage is one JSON file plus a photos folder under STOREFRONT_DATA_DIR.
On a host without a persistent disk the data resets on restart and the POS
republishes its catalog on its next sync.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo

    _SHOP_TZ = ZoneInfo("America/Port-au-Prince")
except Exception:  # tzdata missing on the host
    _SHOP_TZ = timezone(timedelta(hours=-5))

DEFAULT_DAY_USD_RATE = 135.0
SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$")
PHOTO_RE = re.compile(r"^data:image/(png|jpeg|jpg|webp);base64,(.+)$", re.DOTALL)
PHOTO_NAME_RE = re.compile(r"^[a-f0-9]{32}\.(png|jpg|webp)$")
MAX_PHOTO_BYTES = 2_000_000
MAX_PRODUCTS = 2000
MAX_LINES = 100
MAX_QTY = 999
MAX_REQUESTS = 20_000
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")
KINDS = {"devis", "commande"}
# Enterprise types a shop can claim. Same names as the POS picker.
# The directory only offers the ones at least one enabled shop uses.
BUSINESS_CATEGORIES = (
    "Supermarché",
    "Supérette",
    "Épicerie",
    "Magasin de vivres",
    "Boulangerie",
    "Pâtisserie",
    "Boucherie",
    "Charcuterie",
    "Poissonnerie",
    "Fruits et légumes",
    "Produits frais et laitiers",
    "Épicerie fine",
    "Dépôt alimentaire",
    "Dépôt de boissons",
    "Boissons alcoolisées",
    "Eau en bouteille et bonbonnes",
    "Glace et surgelés",
    "Vêtements",
    "Friperie",
    "Chaussures",
    "Sacs et maroquinerie",
    "Tissus et mercerie",
    "Uniformes",
    "Bijouterie",
    "Horlogerie",
    "Articles de cérémonie",
    "Meubles",
    "Literie",
    "Linge de maison",
    "Électroménager",
    "Vaisselle et articles de cuisine",
    "Décoration",
    "Matériaux de construction",
    "Quincaillerie",
    "Bois et menuiserie",
    "Toiture",
    "Peinture",
    "Plomberie et sanitaire",
    "Électricité du bâtiment",
    "Carrelage et revêtements",
    "Portes et fenêtres",
    "Outillage",
    "Générateurs, onduleurs et batteries",
    "Énergie solaire",
    "Gaz domestique",
    "Station-service",
    "Téléphones et accessoires",
    "Informatique",
    "Électronique et audiovisuel",
    "Pièces électroniques",
    "Pharmacie",
    "Parapharmacie",
    "Matériel médical",
    "Optique",
    "Cosmétiques et soins",
    "Parfumerie",
    "Salon de coiffure",
    "Institut de beauté",
    "Articles pour bébé",
    "Jouets",
    "Fournitures scolaires",
    "Pièces automobiles",
    "Pièces moto",
    "Pneus",
    "Lubrifiants",
    "Accessoires auto",
    "Vélos",
    "Intrants agricoles",
    "Semences et plants",
    "Matériel agricole",
    "Irrigation",
    "Aliments pour animaux",
    "Produits vétérinaires",
    "Matériel de pêche",
    "Librairie",
    "Papeterie",
    "Fournitures de bureau",
    "Imprimerie",
    "Articles de sport",
    "Musique et instruments",
    "Artisanat et souvenirs",
    "Jeux",
    "Cadeaux",
    "Fleurs",
    "Location pour événements",
    "Traiteur",
    "Produits d'entretien",
    "Emballages",
    "Animalerie",
    "Sécurité et serrurerie",
    "Pompes funèbres",
    "Magasin général",
    "Grossiste",
    "Import-export",
)
_CATEGORY_SET = set(BUSINESS_CATEGORIES)
_CATEGORY_ORDER = {name: index for index, name in enumerate(BUSINESS_CATEGORIES)}

# Official departments of Haiti. The directory always offers the full list.
DEPARTMENTS = (
    "Artibonite",
    "Centre",
    "Grand'Anse",
    "Nippes",
    "Nord",
    "Nord-Est",
    "Nord-Ouest",
    "Ouest",
    "Sud",
    "Sud-Est",
)
WEEKDAYS_FR = {
    1: "lundi",
    2: "mardi",
    3: "mercredi",
    4: "jeudi",
    5: "vendredi",
    6: "samedi",
    7: "dimanche",
}


class StorefrontError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def day_usd_rate() -> float:
    try:
        value = float(os.environ.get("DAY_USD_RATE") or 0)
    except ValueError:
        value = 0
    return value if value > 0 else DEFAULT_DAY_USD_RATE


def effective_rate(shop: dict) -> float:
    """HTG per 1 USD: the shop's rate, else the day rate."""
    try:
        rate = float(shop.get("usd_rate") or 0)
    except (TypeError, ValueError):
        rate = 0
    return rate if rate > 0 else day_usd_rate()


def htg_to_usd_cents(amount_htg: float, rate: float) -> int:
    if amount_htg <= 0 or rate <= 0:
        return 0
    return int(round(amount_htg / rate * 100))


def key_hash(shop_key: str) -> str:
    key = (shop_key or "").strip()
    if len(key) < 32:
        raise StorefrontError(401, "Clé de boutique invalide.")
    return hashlib.sha256(key.encode()).hexdigest()


def normalize_slug(raw: str) -> str:
    slug = (raw or "").strip().lower()
    if not SLUG_RE.match(slug):
        raise StorefrontError(
            400,
            "Le lien doit faire 3 à 40 caractères : lettres, chiffres ou tirets.",
        )
    return slug


def _text(value: object, limit: int) -> str:
    return str(value or "").strip()[:limit]


def _department(value: object) -> str:
    text = _text(value, 40)
    return text if text in DEPARTMENTS else ""


def _categories(value: object) -> list[str]:
    """Known enterprise types, in the order the shop selected them."""
    if not isinstance(value, list):
        return []
    chosen: list[str] = []
    for item in value:
        name = _text(item, 80)
        if name in _CATEGORY_SET and name not in chosen:
            chosen.append(name)
        if len(chosen) >= 20:
            break
    return chosen


def _phone_digits(value: object) -> str:
    digits = re.sub(r"\D", "", str(value or ""))
    if len(digits) < 8:
        raise StorefrontError(400, "Indiquez un numéro de téléphone valide.")
    return digits


# iso, calling code, national length, required prefixes (NANP), French name.
# The country the visitor picks is stored on the account at registration.
LOGIN_COUNTRIES: tuple[tuple[str, str, int, int, tuple[str, ...], str], ...] = (
    ("HT", "509", 8, 8, (), "Haïti"),
    ("AR", "54", 10, 10, (), "Argentine"),
    ("BS", "1", 10, 10, ("242",), "Bahamas"),
    ("BE", "32", 8, 9, (), "Belgique"),
    ("BR", "55", 10, 11, (), "Brésil"),
    ("CA", "1", 10, 10, (), "Canada"),
    ("CL", "56", 9, 9, (), "Chili"),
    ("CO", "57", 10, 10, (), "Colombie"),
    ("CU", "53", 8, 8, (), "Cuba"),
    ("DE", "49", 10, 11, (), "Allemagne"),
    ("DO", "1", 10, 10, ("809", "829", "849"), "République dominicaine"),
    ("ES", "34", 9, 9, (), "Espagne"),
    ("FR", "33", 9, 9, (), "France"),
    ("GB", "44", 10, 10, (), "Royaume-Uni"),
    ("GF", "594", 9, 9, (), "Guyane"),
    ("GP", "590", 9, 9, (), "Guadeloupe"),
    ("GY", "592", 7, 7, (), "Guyana"),
    ("IT", "39", 9, 10, (), "Italie"),
    ("JM", "1", 10, 10, ("658", "876"), "Jamaïque"),
    ("MF", "590", 9, 9, (), "Saint-Martin"),
    ("MQ", "596", 9, 9, (), "Martinique"),
    ("MX", "52", 10, 10, (), "Mexique"),
    ("NL", "31", 9, 9, (), "Pays-Bas"),
    ("PA", "507", 7, 8, (), "Panama"),
    ("PE", "51", 9, 9, (), "Pérou"),
    ("PR", "1", 10, 10, ("787", "939"), "Porto Rico"),
    ("PT", "351", 9, 9, (), "Portugal"),
    ("BL", "590", 9, 9, (), "Saint-Barthélemy"),
    ("CH", "41", 9, 9, (), "Suisse"),
    ("SR", "597", 6, 7, (), "Suriname"),
    ("TT", "1", 10, 10, ("868",), "Trinité-et-Tobago"),
    ("US", "1", 10, 10, (), "États-Unis"),
    ("VE", "58", 10, 10, (), "Venezuela"),
)
_LOGIN_COUNTRY = {row[0]: row for row in LOGIN_COUNTRIES}


def _login_phone(phone: object, country: object) -> tuple[str, str, str]:
    """Return (iso, e164, digits) for a national number and a chosen country."""
    iso = str(country or "").strip().upper()
    row = _LOGIN_COUNTRY.get(iso)
    if row is None:
        raise StorefrontError(400, "Choisissez un pays.")
    _, dial, low, high, prefixes, _name = row
    national = re.sub(r"\D", "", str(phone or ""))
    if national.startswith(dial) and low <= len(national) - len(dial) <= high:
        national = national[len(dial) :]
    if national.startswith("0") and low <= len(national) - 1 <= high:
        national = national[1:]
    if not (low <= len(national) <= high) or (prefixes and not national.startswith(prefixes)):
        raise StorefrontError(400, "Indiquez un numéro de téléphone valide.")
    digits = f"{dial}{national}"
    if len(digits) > 15:
        raise StorefrontError(400, "Indiquez un numéro de téléphone valide.")
    return iso, f"+{digits}", digits


def _email(value: object) -> str:
    text = _text(value, 120)
    if not text:
        return ""
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", text):
        raise StorefrontError(400, "Indiquez un e-mail valide, ou laissez le champ vide.")
    return text


def _pin_hash(phone_digits: str, pin: str) -> str:
    return hashlib.sha256(f"{phone_digits}:{pin}".encode()).hexdigest()


def _money(value: object) -> float:
    try:
        amount = float(value or 0)
    except (TypeError, ValueError):
        return 0.0
    return round(max(0.0, amount), 2)


def _hour(value: object, default: int) -> int:
    try:
        hour = int(value)
    except (TypeError, ValueError):
        return default
    return hour if 0 <= hour <= 23 else default


def is_open_now(shop: dict, now: datetime | None = None) -> bool:
    if not shop.get("enabled") or shop.get("paused"):
        return False
    now = now or datetime.now(_SHOP_TZ)
    if now.isoweekday() in set(shop.get("closed_weekdays") or []):
        return False
    open_h = int(shop.get("open_hour", 8))
    close_h = int(shop.get("close_hour", 18))
    if open_h == close_h:
        return True
    if open_h < close_h:
        return open_h <= now.hour < close_h
    return now.hour >= open_h or now.hour < close_h


def next_open_at(shop: dict, now: datetime | None = None) -> datetime | None:
    now = now or datetime.now(_SHOP_TZ)
    if is_open_now(shop, now) or shop.get("paused") or not shop.get("enabled"):
        return None
    closed = set(shop.get("closed_weekdays") or [])
    open_h = int(shop.get("open_hour", 8))
    for delta in range(0, 8):
        day = now + timedelta(days=delta)
        if day.isoweekday() in closed:
            continue
        candidate = day.replace(hour=open_h, minute=0, second=0, microsecond=0)
        if candidate > now:
            return candidate
    return None


def opens_at_label(now: datetime, nxt: datetime | None) -> str | None:
    if nxt is None:
        return None
    hour = f"{nxt.hour}h"
    if nxt.date() == now.date():
        return f"à {hour}"
    if nxt.date() == (now + timedelta(days=1)).date():
        return f"demain à {hour}"
    return f"{WEEKDAYS_FR.get(nxt.isoweekday(), '')} à {hour}".strip()


def availability(shop: dict, now: datetime | None = None) -> dict:
    now = now or datetime.now(_SHOP_TZ)
    open_now = is_open_now(shop, now)
    paused = bool(shop.get("paused"))
    enabled = bool(shop.get("enabled"))
    accepts = enabled and not paused and (open_now or bool(shop.get("accept_when_closed")))
    nxt = next_open_at(shop, now)
    return {
        "is_open_now": open_now,
        "paused": paused,
        "accepts_orders": accepts,
        "accepts_quotes": enabled and not paused,
        "accept_when_closed": bool(shop.get("accept_when_closed")),
        "opens_at_label": opens_at_label(now, nxt),
        "open_hour": int(shop.get("open_hour", 8)),
        "close_hour": int(shop.get("close_hour", 18)),
        "closed_weekdays": list(shop.get("closed_weekdays") or []),
    }


class StorefrontStore:
    def __init__(self, data_dir: str):
        self.data_dir = data_dir
        self.photo_dir = os.path.join(data_dir, "photos")
        self._path = os.path.join(data_dir, "storefront.json")
        self._lock = threading.RLock()
        self.shops: dict[str, dict] = {}
        self.slugs: dict[str, str] = {}
        self.requests: dict[str, dict] = {}
        self.accounts: dict[str, dict] = {}
        self.tokens: dict[str, str] = {}
        # Signup tokens stay in memory. A restart invalidates them.
        self._signups: dict[str, dict] = {}
        self._load()

    # ---- persistence -------------------------------------------------------

    def _load(self) -> None:
        try:
            with open(self._path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError):
            return
        if not isinstance(data, dict):
            return
        self.shops = dict(data.get("shops") or {})
        self.slugs = dict(data.get("slugs") or {})
        self.requests = dict(data.get("requests") or {})
        self.accounts = dict(data.get("accounts") or {})
        self.tokens = dict(data.get("tokens") or {})

    def _save(self) -> None:
        os.makedirs(self.data_dir, exist_ok=True)
        tmp = f"{self._path}.tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "shops": self.shops,
                    "slugs": self.slugs,
                    "requests": self.requests,
                    "accounts": self.accounts,
                    "tokens": self.tokens,
                },
                fh,
                ensure_ascii=False,
            )
        os.replace(tmp, self._path)

    # ---- photos ------------------------------------------------------------

    def save_photo(self, data_url: str) -> str:
        match = PHOTO_RE.match((data_url or "").strip())
        if not match:
            return ""
        ext = {"jpeg": "jpg", "jpg": "jpg", "png": "png", "webp": "webp"}[match.group(1)]
        try:
            raw = base64.b64decode(match.group(2), validate=False)
        except (binascii.Error, ValueError):
            return ""
        if not raw or len(raw) > MAX_PHOTO_BYTES:
            return ""
        name = f"{hashlib.sha256(raw).hexdigest()[:32]}.{ext}"
        path = os.path.join(self.photo_dir, name)
        if not os.path.exists(path):
            os.makedirs(self.photo_dir, exist_ok=True)
            with open(path, "wb") as fh:
                fh.write(raw)
        return f"/storefront/photos/{name}"

    def read_photo(self, name: str) -> tuple[bytes, str]:
        if not PHOTO_NAME_RE.match(name or ""):
            raise StorefrontError(404, "Photo introuvable.")
        path = os.path.join(self.photo_dir, name)
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
        except OSError as exc:
            raise StorefrontError(404, "Photo introuvable.") from exc
        mime = {"png": "image/png", "jpg": "image/jpeg", "webp": "image/webp"}[name.rsplit(".", 1)[1]]
        return raw, mime

    def _photo(self, value: object, missing: list[str]) -> str:
        """Data URLs are stored; known photo paths are kept when the file exists.

        A path whose file is gone (fresh disk) is reported in [missing] so
        the POS sends the image again.
        """
        text = str(value or "").strip()
        if text.startswith("data:"):
            return self.save_photo(text)
        name = text.rsplit("/", 1)[-1]
        if text.startswith("/storefront/photos/") and PHOTO_NAME_RE.match(name):
            if os.path.exists(os.path.join(self.photo_dir, name)):
                return text
            missing.append(text)
        return ""

    # ---- shop (authenticated by key) ---------------------------------------

    def slug_available(self, shop_key: str, raw_slug: str) -> bool:
        owner = key_hash(shop_key)
        slug = normalize_slug(raw_slug)
        with self._lock:
            return self.slugs.get(slug) in (None, owner)

    def publish(self, shop_key: str, payload: dict) -> dict:
        owner = key_hash(shop_key)
        slug = normalize_slug(str(payload.get("slug") or ""))
        settings = payload.get("settings") if isinstance(payload.get("settings"), dict) else {}
        name = _text(payload.get("name"), 80)
        if not name:
            raise StorefrontError(400, "Le nom de la boutique est requis.")
        missing: list[str] = []
        products = self._clean_products(payload.get("products"), missing)
        cover = self._photo(settings.get("cover"), missing)
        closed = sorted(
            {int(d) for d in (settings.get("closed_weekdays") or []) if str(d).isdigit() and 1 <= int(d) <= 7}
        )
        try:
            rate = float(payload.get("usd_rate") or 0)
        except (TypeError, ValueError):
            rate = 0
        with self._lock:
            holder = self.slugs.get(slug)
            if holder not in (None, owner):
                raise StorefrontError(409, "Ce lien est déjà pris. Choisissez-en un autre.")
            previous = self.shops.get(owner) or {}
            old_slug = previous.get("slug")
            if old_slug and old_slug != slug and self.slugs.get(old_slug) == owner:
                del self.slugs[old_slug]
            shop = {
                "slug": slug,
                "name": name,
                "phone": _text(payload.get("phone"), 40),
                "address": _text(payload.get("address"), 160),
                "city": _text(payload.get("city") or settings.get("city"), 60),
                "department": _department(payload.get("department") or settings.get("department")),
                "categories": _categories(
                    payload.get("categories")
                    if payload.get("categories") is not None
                    else settings.get("categories")
                ),
                "description": _text(settings.get("description"), 300),
                "pickup_note": _text(settings.get("pickup_note"), 300),
                "cover_url": cover,
                "enabled": bool(settings.get("enabled")),
                "paused": bool(settings.get("paused")),
                "accept_when_closed": bool(settings.get("accept_when_closed", True)),
                "open_hour": _hour(settings.get("open_hour"), 8),
                "close_hour": _hour(settings.get("close_hour"), 18),
                "closed_weekdays": closed,
                "usd_rate": rate if rate > 0 else 0,
                "products": products,
                "published_at": int(time.time()),
            }
            self.shops[owner] = shop
            self.slugs[slug] = owner
            self._save()
        return {
            "slug": slug,
            "published_at": shop["published_at"],
            "products": len(products),
            "missing_photos": missing,
        }

    def _clean_products(self, raw: object, missing: list[str]) -> list[dict]:
        if not isinstance(raw, list):
            return []
        cleaned: list[dict] = []
        seen: set[str] = set()
        for item in raw[:MAX_PRODUCTS]:
            if not isinstance(item, dict):
                continue
            pid = _text(item.get("id"), 40)
            name = _text(item.get("name"), 120)
            price = _money(item.get("price_htg"))
            if not pid or not name or price <= 0 or pid in seen:
                continue
            seen.add(pid)
            track = bool(item.get("track_stock", True))
            try:
                stock = int(item.get("stock") or 0)
            except (TypeError, ValueError):
                stock = 0
            groups: list[dict] = []
            for group in (item.get("options") or [])[:12]:
                if not isinstance(group, dict):
                    continue
                choices = []
                for choice in (group.get("choices") or [])[:30]:
                    if not isinstance(choice, dict):
                        continue
                    cid = _text(choice.get("id"), 80)
                    cname = _text(choice.get("name"), 60)
                    if cid and cname:
                        choices.append({"id": cid, "name": cname, "delta_htg": _money(choice.get("delta_htg"))})
                gid = _text(group.get("id"), 80)
                gname = _text(group.get("name"), 60)
                if gid and gname and choices:
                    groups.append(
                        {
                            "id": gid,
                            "name": gname,
                            "required": bool(group.get("required")),
                            "multiple": bool(group.get("multiple")),
                            "choices": choices,
                        }
                    )
            regular = _money(item.get("regular_price_htg"))
            sale = self._sale_fields(item)
            if sale is None:
                continue
            cleaned.append(
                {
                    "id": pid,
                    "name": name,
                    "category": _text(item.get("category"), 60) or "Autres",
                    "description": _text(item.get("description"), 600),
                    "price_htg": price,
                    "regular_price_htg": regular if regular > price else 0,
                    "photo_url": self._photo(item.get("photo"), missing),
                    "track_stock": track,
                    "stock": max(0, stock),
                    "unit": _text(item.get("unit"), 12),
                    "options": groups,
                    **sale,
                }
            )
        return cleaned

    def _sale_fields(self, item: dict) -> dict | None:
        """None when a roll or a case is missing the numbers it needs to sell."""
        mode = str(item.get("sale_mode") or "piece")
        if mode == "roll":
            roll_price = _money(item.get("roll_price_htg"))
            try:
                roll_width = int(item.get("roll_width") or 0)
                min_width = int(item.get("min_width") or 0)
            except (TypeError, ValueError):
                return None
            if roll_price <= 0 or roll_width < 1 or min_width < 1 or min_width > roll_width:
                return None
            regular_roll = _money(item.get("regular_roll_price_htg"))
            return {
                "sale_mode": "roll",
                "roll_price_htg": roll_price,
                "regular_roll_price_htg": regular_roll if regular_roll > roll_price else 0,
                "roll_width": roll_width,
                "min_width": min_width,
                "case_price_htg": 0,
                "regular_case_price_htg": 0,
                "units_per_case": 0,
            }
        if mode == "case":
            case_price = _money(item.get("case_price_htg"))
            try:
                units = int(item.get("units_per_case") or 0)
            except (TypeError, ValueError):
                return None
            if case_price <= 0 or units < 2:
                return None
            regular_case = _money(item.get("regular_case_price_htg"))
            return {
                "sale_mode": "case",
                "roll_price_htg": 0,
                "regular_roll_price_htg": 0,
                "roll_width": 0,
                "min_width": 0,
                "case_price_htg": case_price,
                "regular_case_price_htg": regular_case if regular_case > case_price else 0,
                "units_per_case": units,
            }
        return {
            "sale_mode": "piece",
            "roll_price_htg": 0,
            "regular_roll_price_htg": 0,
            "roll_width": 0,
            "min_width": 0,
            "case_price_htg": 0,
            "regular_case_price_htg": 0,
            "units_per_case": 0,
        }

    def shop_for_key(self, shop_key: str) -> dict:
        owner = key_hash(shop_key)
        with self._lock:
            shop = self.shops.get(owner)
        if not shop:
            raise StorefrontError(404, "Vitrine non publiée.")
        return shop

    def inbox(self, shop_key: str) -> list[dict]:
        owner = key_hash(shop_key)
        with self._lock:
            rows = [r for r in self.requests.values() if r.get("shop") == owner]
        rows.sort(key=lambda r: r.get("created_at", 0), reverse=True)
        return [self._shop_view(r) for r in rows[:300]]

    def create_shop_request(self, shop_key: str, payload: dict) -> dict:
        """A devis or commande prepared at the register, to share by link.

        The shop sets its own prices (discounts, negotiated quotes), so lines
        are taken as sent once the key is verified.
        """
        owner = key_hash(shop_key)
        with self._lock:
            shop = self.shops.get(owner)
        if not shop:
            raise StorefrontError(409, "Publiez d'abord la vitrine pour partager un lien.")
        kind = str(payload.get("kind") or "devis")
        if kind not in KINDS:
            raise StorefrontError(400, "Type de demande inconnu.")
        lines: list[dict] = []
        for raw in (payload.get("lines") or [])[:MAX_LINES]:
            if not isinstance(raw, dict):
                continue
            qty = int(raw.get("quantity") or 0)
            unit = _money(raw.get("unit_htg"))
            name = _text(raw.get("name"), 120)
            if qty < 1 or qty > MAX_QTY or unit <= 0 or not name:
                continue
            lines.append(
                {
                    "product_id": _text(raw.get("product_id"), 40),
                    "name": name,
                    "options": [],
                    "options_label": _text(raw.get("options_label"), 200),
                    "quantity": qty,
                    "unit_htg": unit,
                    "total_htg": round(unit * qty, 2),
                }
            )
        if not lines:
            raise StorefrontError(400, "Ajoutez au moins un article.")
        subtotal = round(sum(l["total_htg"] for l in lines), 2)
        discount = min(_money(payload.get("discount_htg")), subtotal)
        external = _text(payload.get("reference"), 40)
        with self._lock:
            if external:
                for existing in self.requests.values():
                    if existing.get("shop") == owner and existing.get("external_ref") == external:
                        if existing.get("status") != "paid":
                            existing["lines"] = lines
                            existing["discount_htg"] = discount
                            existing["total_htg"] = round(subtotal - discount, 2)
                            existing["usd_rate"] = effective_rate(shop)
                            self._save()
                        return self._public_view(existing)
            request = self._new_request(
                owner,
                shop,
                kind=kind,
                lines=lines,
                discount=discount,
                customer=payload.get("customer"),
                note=_text(payload.get("note"), 500),
                source="pos",
            )
            request["external_ref"] = external
            request["number"] = _text(payload.get("number"), 30) or request["number"]
            self._save()
        return self._public_view(request)

    # ---- public ------------------------------------------------------------

    def directory(self, department: str = "", now: datetime | None = None) -> dict:
        """Public list of enabled vitrines. Disabled shops stay hidden."""
        raw = _text(department, 40)
        wanted = _department(raw)
        with self._lock:
            shops = [dict(shop) for shop in self.shops.values() if shop.get("enabled")]
        shops.sort(key=lambda shop: str(shop.get("name") or "").lower())
        used: list[str] = []
        for shop in shops:
            for name in shop.get("categories") or []:
                if name not in used:
                    used.append(name)
        used.sort(key=lambda name: _CATEGORY_ORDER.get(name, 10_000))
        if raw and not wanted:
            shops = []
        elif wanted:
            shops = [shop for shop in shops if shop.get("department") == wanted]
        return {
            "departments": list(DEPARTMENTS),
            "categories": used,
            "results": [self._directory_card(shop, now) for shop in shops],
        }

    def _directory_card(self, shop: dict, now: datetime | None) -> dict:
        info = availability(shop, now)
        return {
            "slug": shop["slug"],
            "name": shop["name"],
            "city": shop.get("city", ""),
            "department": shop.get("department", ""),
            "categories": list(shop.get("categories") or []),
            "description": shop.get("description", ""),
            "cover_url": shop.get("cover_url", ""),
            "is_open_now": info["is_open_now"],
            "paused": info["paused"],
            "opens_at_label": info["opens_at_label"],
        }

    def public_shop(self, raw_slug: str, now: datetime | None = None) -> dict:
        slug = (raw_slug or "").strip().lower()
        with self._lock:
            owner = self.slugs.get(slug)
            shop = self.shops.get(owner) if owner else None
        if not shop or not shop.get("enabled"):
            raise StorefrontError(404, "Cette vitrine n'est pas disponible.")
        products = [
            {
                "id": p["id"],
                "name": p["name"],
                "category": p["category"],
                "description": p["description"],
                "price_htg": p["price_htg"],
                "regular_price_htg": p.get("regular_price_htg", 0),
                "photo_url": p["photo_url"],
                "available": (not p["track_stock"]) or p["stock"] > 0,
                "max_quantity": min(MAX_QTY, p["stock"]) if p["track_stock"] else MAX_QTY,
                "unit": p.get("unit", ""),
                "options": p["options"],
                "track_stock": p.get("track_stock", True),
                "stock": p.get("stock", 0),
                "sale_mode": p.get("sale_mode", "piece"),
                "roll_price_htg": p.get("roll_price_htg", 0),
                "regular_roll_price_htg": p.get("regular_roll_price_htg", 0),
                "roll_width": p.get("roll_width", 0),
                "min_width": p.get("min_width", 0),
                "case_price_htg": p.get("case_price_htg", 0),
                "regular_case_price_htg": p.get("regular_case_price_htg", 0),
                "units_per_case": p.get("units_per_case", 0),
            }
            for p in shop.get("products") or []
        ]
        categories: list[str] = []
        for product in products:
            if product["category"] not in categories:
                categories.append(product["category"])
        return {
            "slug": shop["slug"],
            "name": shop["name"],
            "phone": shop.get("phone", ""),
            "address": shop.get("address", ""),
            "city": shop.get("city", ""),
            "department": shop.get("department", ""),
            "business_categories": list(shop.get("categories") or []),
            "description": shop.get("description", ""),
            "pickup_note": shop.get("pickup_note", ""),
            "cover_url": shop.get("cover_url", ""),
            "usd_rate": effective_rate(shop),
            "availability": availability(shop, now),
            "categories": categories,
            "products": products,
        }

    def open_account(self, phone: object, pin: object, name: object = "") -> dict:
        """Create a customer account or sign back in with the same personal code."""
        digits = _phone_digits(phone)
        code = str(pin or "").strip()
        if not re.fullmatch(r"\d{4,6}", code):
            raise StorefrontError(400, "Le code personnel doit avoir 4 à 6 chiffres.")
        with self._lock:
            account = self.accounts.get(digits)
            if account is None:
                display = _text(name, 80)
                if not display:
                    raise StorefrontError(400, "Indiquez votre nom pour créer le compte.")
                account = {
                    "phone": _text(phone, 40) or digits,
                    "name": display,
                    "pin_hash": _pin_hash(digits, code),
                    "created_at": int(time.time()),
                }
                self.accounts[digits] = account
            elif account.get("pin_hash") != _pin_hash(digits, code):
                raise StorefrontError(401, "Code personnel incorrect.")
            elif _text(name, 80):
                account["name"] = _text(name, 80)
            token = secrets.token_urlsafe(24)
            self.tokens[hashlib.sha256(token.encode()).hexdigest()] = digits
            self._save()
            view = self._account_view(account)
        return {"token": token, "account": view}

    def request_code(self, phone: object, country: object) -> dict:
        """Accept the number. The code itself is a placeholder until Firebase sends it."""
        _login_phone(phone, country)
        return {"sent": True}

    def verify_code(self, phone: object, country: object, code: object) -> dict:
        """Accept any code. A known account gets a session; a new number gets a signup token."""
        iso, e164, digits = _login_phone(phone, country)
        if not str(code or "").strip():
            raise StorefrontError(400, "Indiquez le code.")
        with self._lock:
            account = self.accounts.get(digits)
            if account and _text(account.get("name"), 80):
                if not account.get("country"):
                    account["country"] = iso
                account.setdefault("email", "")
                token = secrets.token_urlsafe(24)
                self.tokens[hashlib.sha256(token.encode()).hexdigest()] = digits
                self._save()
                return {
                    "registered": True,
                    "token": token,
                    "account": self._account_view(account),
                }
            signup = secrets.token_urlsafe(24)
            self._signups[hashlib.sha256(signup.encode()).hexdigest()] = {
                "digits": digits,
                "phone": e164,
                "country": iso,
                "expires": time.time() + 900,
            }
            return {"registered": False, "signup_token": signup}

    def register_account(self, signup_token: object, name: object, email: object = "") -> dict:
        """Create the account after the phone was confirmed. Country comes from the dial code."""
        display = _text(name, 80)
        if len(display) < 2:
            raise StorefrontError(400, "Indiquez votre nom complet.")
        mail = _email(email)
        digest = hashlib.sha256(str(signup_token or "").encode()).hexdigest()
        with self._lock:
            pending = self._signups.get(digest)
            if not pending or time.time() > float(pending.get("expires") or 0):
                self._signups.pop(digest, None)
                raise StorefrontError(401, "Cette étape a expiré. Recommencez avec votre numéro.")
            self._signups.pop(digest, None)
            digits = pending["digits"]
            account = self.accounts.get(digits) or {"created_at": int(time.time())}
            account["phone"] = pending["phone"]
            account["country"] = pending["country"]
            account["name"] = display
            account["email"] = mail
            self.accounts[digits] = account
            token = secrets.token_urlsafe(24)
            self.tokens[hashlib.sha256(token.encode()).hexdigest()] = digits
            self._save()
            return {"token": token, "account": self._account_view(account)}

    def account_for_token(self, token: str) -> dict:
        with self._lock:
            digits = self.tokens.get(hashlib.sha256((token or "").encode()).hexdigest())
            account = self.accounts.get(digits) if digits else None
            if not account:
                raise StorefrontError(401, "Connexion requise.")
            return self._account_view(account)

    def phone_for_token(self, token: str) -> str:
        with self._lock:
            digits = self.tokens.get(hashlib.sha256((token or "").encode()).hexdigest())
        if not digits:
            raise StorefrontError(401, "Connexion requise.")
        return digits

    def account_phone(self, token: str) -> str:
        """Phone saved with this session. An unknown token does not block an order."""
        if not str(token or "").strip():
            return ""
        try:
            return self.phone_for_token(token)
        except StorefrontError:
            return ""

    def update_account(self, token: str, name: object) -> dict:
        display = _text(name, 80)
        if not display:
            raise StorefrontError(400, "Indiquez votre nom.")
        with self._lock:
            digits = self.phone_for_token(token)
            account = self.accounts[digits]
            account["name"] = display
            self._save()
            return self._account_view(account)

    def account_orders(self, token: str) -> list[dict]:
        digits = self.phone_for_token(token)
        with self._lock:
            rows = [r for r in self.requests.values() if r.get("account_phone") == digits]
            shops = dict(self.shops)
        rows.sort(key=lambda row: int(row.get("created_at") or 0), reverse=True)
        return [self._order_row(row, shops) for row in rows[:200]]

    def _account_view(self, account: dict) -> dict:
        return {
            "name": account.get("name", ""),
            "phone": account.get("phone", ""),
            "country": account.get("country", ""),
            "email": account.get("email", ""),
        }

    def _order_row(self, request: dict, shops: dict) -> dict:
        shop = shops.get(request.get("shop")) or {}
        return {
            "id": request["id"],
            "number": request["number"],
            "kind": request["kind"],
            "status": request["status"],
            "created_at": request["created_at"],
            "shop_name": shop.get("name", ""),
            "shop_slug": shop.get("slug", ""),
            "total_htg": request["total_htg"],
            "usd_rate": request.get("usd_rate") or effective_rate(shop),
        }

    def create_request(
        self,
        raw_slug: str,
        payload: dict,
        now: datetime | None = None,
        account_phone: str = "",
    ) -> dict:
        slug = (raw_slug or "").strip().lower()
        kind = str(payload.get("kind") or "")
        if kind not in KINDS:
            raise StorefrontError(400, "Choisissez devis ou commande.")
        with self._lock:
            owner = self.slugs.get(slug)
            shop = self.shops.get(owner) if owner else None
            if not shop or not shop.get("enabled"):
                raise StorefrontError(404, "Cette vitrine n'est pas disponible.")
            avail = availability(shop, now)
            if kind == "commande" and not avail["accepts_orders"]:
                if avail["paused"]:
                    raise StorefrontError(409, "La boutique a mis les commandes en pause.")
                raise StorefrontError(409, "La boutique est fermée pour le moment.")
            if kind == "devis" and not avail["accepts_quotes"]:
                raise StorefrontError(409, "La boutique n'accepte pas de demandes pour le moment.")
            customer = payload.get("customer") if isinstance(payload.get("customer"), dict) else {}
            if not _text(customer.get("name"), 80):
                raise StorefrontError(400, "Indiquez votre nom.")
            if len(re.sub(r"\D", "", str(customer.get("phone") or ""))) < 8:
                raise StorefrontError(400, "Indiquez un numéro de téléphone valide.")
            email = _text(customer.get("email"), 120)
            if email and not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email):
                raise StorefrontError(400, "L'adresse e-mail n'est pas valide.")
            lines = self._price_lines(shop, payload.get("lines"))
            request = self._new_request(
                owner,
                shop,
                kind=kind,
                lines=lines,
                discount=0,
                customer=customer,
                note=_text(payload.get("note"), 500),
                source="storefront",
                account_phone=account_phone,
            )
            self._save()
        return self._public_view(request)

    def _price_lines(self, shop: dict, raw_lines: object) -> list[dict]:
        if not isinstance(raw_lines, list) or not raw_lines:
            raise StorefrontError(400, "Le panier est vide.")
        catalog = {p["id"]: p for p in shop.get("products") or []}
        wanted: dict[str, int] = {}
        lines: list[dict] = []
        for raw in raw_lines[:MAX_LINES]:
            if not isinstance(raw, dict):
                continue
            product = catalog.get(str(raw.get("product_id") or ""))
            if not product:
                raise StorefrontError(409, "Un article n'est plus proposé. Actualisez la vitrine.")
            try:
                qty = int(raw.get("quantity") or 0)
            except (TypeError, ValueError):
                qty = 0
            if qty < 1 or qty > MAX_QTY:
                raise StorefrontError(400, "Quantité invalide.")
            base, each, measure_label = self._measured_price(product, raw)
            take = each * qty
            wanted[product["id"]] = wanted.get(product["id"], 0) + take
            if product["track_stock"] and wanted[product["id"]] > product["stock"]:
                if product["stock"] <= 0:
                    raise StorefrontError(409, f"{product['name']} est en rupture de stock.")
                mode = product.get("sale_mode") or "piece"
                if mode == "roll":
                    raise StorefrontError(
                        409, f"Il reste {product['stock']} po de {product['name']}."
                    )
                if mode == "case":
                    raise StorefrontError(
                        409, f"Il reste {product['stock']} unités de {product['name']}."
                    )
                raise StorefrontError(
                    409, f"Il reste {product['stock']} × {product['name']} en stock."
                )
            picked = {str(c) for c in (raw.get("choices") or []) if c}
            chosen: list[dict] = []
            extra = 0.0
            for group in product["options"]:
                in_group = [c for c in group["choices"] if c["id"] in picked]
                if group["required"] and not in_group:
                    raise StorefrontError(400, f"Choisissez « {group['name']} » pour {product['name']}.")
                if not group["multiple"] and len(in_group) > 1:
                    raise StorefrontError(400, f"Une seule option « {group['name']} » est possible.")
                for choice in in_group:
                    chosen.append({"group": group["name"], "id": choice["id"], "name": choice["name"]})
                    extra += choice["delta_htg"]
            unit = round(base + extra, 2)
            label_parts = [measure_label] if measure_label else []
            label_parts.extend(c["name"] for c in chosen)
            lines.append(
                {
                    "product_id": product["id"],
                    "name": product["name"],
                    "options": chosen,
                    "options_label": ", ".join(label_parts),
                    "quantity": qty,
                    "unit_htg": unit,
                    "total_htg": round(unit * qty, 2),
                    "stock_units": take,
                }
            )
        if not lines:
            raise StorefrontError(400, "Le panier est vide.")
        return lines

    def _measured_price(self, product: dict, raw: dict) -> tuple[float, int, str]:
        """Returns the unit price, the stock taken by one quantity, and the label."""
        mode = product.get("sale_mode") or "piece"
        measure = str(raw.get("measure") or "")
        name = product["name"]
        try:
            width = int(float(raw.get("width") or 0))
        except (TypeError, ValueError):
            width = 0
        if mode == "roll":
            if measure == "roll":
                return product["roll_price_htg"], int(product["roll_width"]), "Rouleau entier"
            if measure == "cut":
                minimum = int(product["min_width"])
                if width < minimum:
                    raise StorefrontError(
                        400, f"La largeur minimum pour {name} est {minimum} po."
                    )
                if width > 10000:
                    raise StorefrontError(400, "Cette largeur est trop grande.")
                return round(product["price_htg"] * width, 2), width, f"{width} po"
            raise StorefrontError(
                400, f"Choisissez le rouleau entier ou une largeur pour {name}."
            )
        if mode == "case":
            if measure == "case":
                count = int(product["units_per_case"])
                return product["case_price_htg"], count, f"Caisse de {count}"
            if measure in ("", "unit"):
                return product["price_htg"], 1, "À l'unité"
            raise StorefrontError(400, f"Choisissez une caisse ou une unité pour {name}.")
        return product["price_htg"], 1, ""

    def _new_request(
        self,
        owner: str,
        shop: dict,
        *,
        kind: str,
        lines: list[dict],
        discount: float,
        customer: object,
        note: str,
        source: str,
        account_phone: str = "",
    ) -> dict:
        customer = customer if isinstance(customer, dict) else {}
        subtotal = round(sum(l["total_htg"] for l in lines), 2)
        prefix = "DEV" if kind == "devis" else "CMD"
        request_id = secrets.token_urlsafe(18)
        while request_id in self.requests:
            request_id = secrets.token_urlsafe(18)
        request = {
            "id": request_id,
            "number": f"{prefix}-{secrets.token_hex(3).upper()}",
            "shop": owner,
            "kind": kind,
            "status": "open",
            "source": source,
            "created_at": int(time.time()),
            "customer": {
                "name": _text(customer.get("name"), 80),
                "phone": _text(customer.get("phone"), 40),
                "email": _text(customer.get("email"), 120),
            },
            "note": note,
            "account_phone": account_phone,
            "lines": lines,
            "discount_htg": discount,
            "total_htg": round(subtotal - discount, 2),
            "usd_rate": effective_rate(shop),
            "paid_at": 0,
            "payment": {},
            "card_intent_id": "",
            "moncash_order_id": "",
        }
        self.requests[request_id] = request
        self._prune()
        return request

    def _prune(self) -> None:
        if len(self.requests) <= MAX_REQUESTS:
            return
        stale = sorted(
            (r for r in self.requests.values() if r.get("status") != "paid"),
            key=lambda r: r.get("created_at", 0),
        )
        for row in stale[: len(self.requests) - MAX_REQUESTS]:
            self.requests.pop(row["id"], None)

    # ---- request lifecycle -------------------------------------------------

    def _get(self, request_id: str) -> dict:
        if not REQUEST_ID_RE.match(request_id or ""):
            raise StorefrontError(404, "Ce lien n'existe pas ou a expiré.")
        request = self.requests.get(request_id)
        if not request:
            raise StorefrontError(404, "Ce lien n'existe pas ou a expiré.")
        return request

    def get_request(self, request_id: str) -> dict:
        with self._lock:
            return self._public_view(self._get(request_id))

    def payable(self, request_id: str) -> dict:
        """Internal record for payment. Raises when already paid."""
        with self._lock:
            request = self._get(request_id)
            if request.get("status") == "paid":
                raise StorefrontError(409, "Cette demande est déjà payée.")
            if request["total_htg"] <= 0:
                raise StorefrontError(400, "Le montant doit être supérieur à zéro.")
            return dict(request)

    def card_order_cents(self, request: dict) -> int:
        return htg_to_usd_cents(request["total_htg"], float(request.get("usd_rate") or day_usd_rate()))

    def moncash_amount(self, request: dict) -> int:
        return int(round(request["total_htg"]))

    def attach(self, request_id: str, **fields: str) -> None:
        with self._lock:
            request = self._get(request_id)
            for key in ("card_intent_id", "moncash_order_id"):
                if key in fields:
                    request[key] = fields[key]
            self._save()

    def mark_paid(self, request_id: str, *, method: str, reference: str, amount: int, currency: str) -> dict:
        with self._lock:
            request = self._get(request_id)
            if request.get("status") != "paid":
                request["status"] = "paid"
                request["paid_at"] = int(time.time())
                request["payment"] = {
                    "method": method,
                    "reference": reference[:120],
                    "amount": int(amount),
                    "currency": currency,
                }
                self._save()
            return self._public_view(request)

    def moncash_order_id(self, request_id: str) -> str:
        with self._lock:
            return str(self._get(request_id).get("moncash_order_id") or "")

    # ---- views -------------------------------------------------------------

    def _public_view(self, request: dict) -> dict:
        shop = self.shops.get(request["shop"]) or {}
        rate = float(request.get("usd_rate") or day_usd_rate())
        payment = request.get("payment") or {}
        return {
            "id": request["id"],
            "number": request["number"],
            "kind": request["kind"],
            "status": request["status"],
            "created_at": request["created_at"],
            "paid_at": request.get("paid_at") or 0,
            "payment_method": payment.get("method", ""),
            "customer_name": request["customer"].get("name", ""),
            "note": request.get("note", ""),
            "lines": [
                {
                    "name": l["name"],
                    "options_label": l.get("options_label", ""),
                    "quantity": l["quantity"],
                    "unit_htg": l["unit_htg"],
                    "total_htg": l["total_htg"],
                    "stock_units": l.get("stock_units", l["quantity"]),
                }
                for l in request["lines"]
            ],
            "discount_htg": request.get("discount_htg", 0),
            "total_htg": request["total_htg"],
            "usd_rate": rate,
            "order_usd_cents": htg_to_usd_cents(request["total_htg"], rate),
            "moncash_htg": int(round(request["total_htg"])),
            "shop": {
                "slug": shop.get("slug", ""),
                "name": shop.get("name", ""),
                "phone": shop.get("phone", ""),
                "pickup_note": shop.get("pickup_note", ""),
                "cover_url": shop.get("cover_url", ""),
            },
        }

    def _shop_view(self, request: dict) -> dict:
        view = self._public_view(request)
        view.pop("shop", None)
        view["customer"] = dict(request["customer"])
        view["source"] = request.get("source", "storefront")
        view["external_ref"] = request.get("external_ref", "")
        view["payment"] = dict(request.get("payment") or {})
        view["lines"] = [
            {
                "product_id": l.get("product_id", ""),
                "name": l["name"],
                "options_label": l.get("options_label", ""),
                "quantity": l["quantity"],
                "unit_htg": l["unit_htg"],
                "total_htg": l["total_htg"],
                "stock_units": l.get("stock_units", l["quantity"]),
            }
            for l in request["lines"]
        ]
        return view

"""Vitrine: publish, browse, request, pay, and turn paid requests into orders.

Prices are always recomputed from the catalog; client totals are never
trusted. A commande reserves its stock when it is placed so two shoppers
cannot buy the last unit; unpaid reservations lapse after
STOREFRONT_RESERVATION_MINUTES and are taken again at payment time.
"""

from __future__ import annotations

import hmac
import logging
import re
import secrets
from datetime import datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.conf import settings
from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.db.models import Prefetch
from django.utils import timezone

from apps.accounts.models import Business, BusinessSettings, Location
from apps.accounts.security import hash_token, new_token
from apps.catalog.models import Category, Product, ProductOptionChoice, ProductOptionGroup, StockMovement
from apps.catalog.pricing import price_line, stock_shortage_message
from apps.catalog.stock import adjust_stock
from apps.common.actors import SystemActor
from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.images import public_image_exists, public_image_url, save_public_image
from apps.common.money import ZERO, as_float, htg_to_usd_cents, money, whole_htg
from apps.common.numbering import next_number

from . import cache as sf_cache
from .constants import (
    CATEGORY_ORDER,
    CATEGORY_SET,
    DEPARTMENTS,
    MAX_LINES,
    MAX_PRODUCTS,
    MAX_QTY,
    REQUEST_ID_RE,
    SLUG_RE,
    WEEKDAYS_FR,
)
from .models import ShopperAccount, ShopperSession, ShopperSignup, StorefrontRequest, StorefrontShop
from .phone import check_code, send_code

log = logging.getLogger(__name__)
SHOP_TZ = ZoneInfo("America/Port-au-Prince")
SIGNUP_MINUTES = 15
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _text(value: object, limit: int) -> str:
    return str(value or "").strip()[:limit]


def _epoch(value) -> int:
    return int(value.timestamp()) if value else 0


def key_hash(shop_key: str) -> str:
    key = (shop_key or "").strip()
    if len(key) < 32:
        raise ApiError("Clé de boutique invalide.", 401)
    return hash_token(key)


def normalize_slug(raw: str) -> str:
    slug = (raw or "").strip().lower()
    if not SLUG_RE.match(slug):
        raise ApiError("Le lien doit faire 3 à 40 caractères : lettres, chiffres ou tirets.")
    return slug


def clean_department(value: object) -> str:
    text = _text(value, 40)
    return text if text in DEPARTMENTS else ""


def clean_categories(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    chosen: list[str] = []
    for item in value:
        name = _text(item, 80)
        if name in CATEGORY_SET and name not in chosen:
            chosen.append(name)
        if len(chosen) >= 20:
            break
    return chosen


def clean_email(value: object) -> str:
    text = _text(value, 120)
    if text and not EMAIL_RE.match(text):
        raise ApiError("Indiquez un e-mail valide, ou laissez le champ vide.")
    return text


def _hour(value: object, default: int) -> int:
    try:
        hour = int(value)
    except (TypeError, ValueError):
        return default
    return hour if 0 <= hour <= 23 else default


# --- Opening hours ---------------------------------------------------------------


def is_open_now(shop: StorefrontShop, now: datetime | None = None) -> bool:
    if not shop.enabled or shop.paused:
        return False
    now = now or datetime.now(SHOP_TZ)
    if now.isoweekday() in set(shop.closed_weekdays or []):
        return False
    if shop.open_hour == shop.close_hour:
        return True
    if shop.open_hour < shop.close_hour:
        return shop.open_hour <= now.hour < shop.close_hour
    return now.hour >= shop.open_hour or now.hour < shop.close_hour


def next_open_at(shop: StorefrontShop, now: datetime | None = None) -> datetime | None:
    now = now or datetime.now(SHOP_TZ)
    if is_open_now(shop, now) or shop.paused or not shop.enabled:
        return None
    closed = set(shop.closed_weekdays or [])
    for delta in range(0, 8):
        day = now + timedelta(days=delta)
        if day.isoweekday() in closed:
            continue
        candidate = day.replace(hour=shop.open_hour, minute=0, second=0, microsecond=0)
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


def availability(shop: StorefrontShop, now: datetime | None = None) -> dict:
    now = now or datetime.now(SHOP_TZ)
    open_now = is_open_now(shop, now)
    return {
        "is_open_now": open_now,
        "paused": shop.paused,
        "accepts_orders": shop.enabled and not shop.paused and (open_now or shop.accept_when_closed),
        "accepts_quotes": shop.enabled and not shop.paused,
        "accept_when_closed": shop.accept_when_closed,
        "opens_at_label": opens_at_label(now, next_open_at(shop, now)),
        "open_hour": shop.open_hour,
        "close_hour": shop.close_hour,
        "closed_weekdays": list(shop.closed_weekdays or []),
    }


# --- Shop settings -----------------------------------------------------------------


def shop_for_key(shop_key: str) -> StorefrontShop | None:
    return StorefrontShop.objects.select_related("business__settings").filter(key_hash=key_hash(shop_key)).first()


def shop_for_business(business: Business) -> StorefrontShop:
    shop = StorefrontShop.objects.filter(business=business).first()
    if shop is None:
        shop = StorefrontShop.objects.create(business=business, name=business.name[:80], phone=business.phone,
                                             address=business.address[:160], city=business.city,
                                             department=clean_department(business.department))
    return shop


def slug_available(slug: str, shop: StorefrontShop | None) -> bool:
    holder = StorefrontShop.objects.filter(slug=normalize_slug(slug)).values_list("pk", flat=True).first()
    return holder is None or (shop is not None and holder == shop.pk)


def _closed_days(raw) -> list[int]:
    return sorted({int(d) for d in (raw or []) if str(d).isdigit() and 1 <= int(d) <= 7})


def apply_shop_settings(shop: StorefrontShop, data: dict, missing: list[str] | None = None) -> StorefrontShop:
    """Shared by the staff settings screen and the legacy publish payload."""
    missing = missing if missing is not None else []
    if "slug" in data:
        slug = normalize_slug(str(data.get("slug") or ""))
        if not slug_available(slug, shop):
            raise ApiError("Ce lien est déjà pris. Choisissez-en un autre.", 409)
        shop.slug = slug
    if "name" in data:
        name = _text(data.get("name"), 80)
        if not name:
            raise ApiError("Le nom de la boutique est requis.")
        shop.name = name
    for field, limit in (("phone", 40), ("address", 160), ("city", 60), ("description", 300), ("pickup_note", 300)):
        if field in data:
            setattr(shop, field, _text(data.get(field), limit))
    if "department" in data:
        shop.department = clean_department(data.get("department"))
    if "categories" in data and data.get("categories") is not None:
        shop.categories = clean_categories(data.get("categories"))
    for flag in ("enabled", "paused", "accept_when_closed"):
        if flag in data:
            setattr(shop, flag, bool(data.get(flag)))
    if "open_hour" in data:
        shop.open_hour = _hour(data.get("open_hour"), 8)
    if "close_hour" in data:
        shop.close_hour = _hour(data.get("close_hour"), 18)
    if "closed_weekdays" in data:
        shop.closed_weekdays = _closed_days(data.get("closed_weekdays"))
    if "usd_rate" in data:
        rate = money(data.get("usd_rate"))
        shop.usd_rate = rate if rate > 0 else ZERO
    if "cover" in data:
        shop.cover = _photo_name(data.get("cover"), missing)
    try:
        with transaction.atomic():
            shop.save()
    except IntegrityError as exc:
        raise ApiError("Ce lien est déjà pris. Choisissez-en un autre.", 409) from exc
    sf_cache.invalidate_shop(shop.business_id)
    return shop


def rotate_shop_key(shop: StorefrontShop) -> str:
    raw = new_token()
    shop.key_hash = hash_token(raw)
    shop.save(update_fields=["key_hash", "updated_at"])
    return raw


def _photo_name(value: object, missing: list[str]) -> str:
    """Data URLs are stored. Known photo paths are kept when the file exists;
    a path whose file is gone is reported so the register sends it again."""
    text = str(value or "").strip()
    if text.startswith("data:"):
        return save_public_image(text)
    name = text.rsplit("/", 1)[-1]
    if text.startswith("/storefront/photos/") or (name and "/" not in text):
        if public_image_exists(name):
            return name
        if text.startswith("/storefront/photos/"):
            missing.append(text)
    return ""


# --- Legacy publish (X-Shop-Key) ------------------------------------------------------


def _legacy_business(name: str) -> Business:
    business = Business.objects.create(name=name[:120])
    BusinessSettings.objects.create(business=business, receipt_name=name[:120])
    Location.objects.create(business=business, name=name[:120], is_default=True)
    return business


def _sale_fields(item: dict) -> dict | None:
    mode = str(item.get("sale_mode") or "piece")
    blank = {"sale_mode": Product.PIECE, "roll_price_htg": ZERO, "regular_roll_price_htg": ZERO, "roll_width": 0,
             "min_width": 0, "limit_length": False, "case_price_htg": ZERO, "regular_case_price_htg": ZERO,
             "units_per_case": 0}
    try:
        if mode == "roll":
            roll_price = money(item.get("roll_price_htg"))
            roll_width = int(item.get("roll_width") or 0)
            min_width = int(item.get("min_width") or 0)
            if roll_price <= 0 or roll_width < 1 or min_width < 1 or min_width > roll_width:
                return None
            return {**blank, "sale_mode": Product.ROLL, "roll_price_htg": roll_price,
                    "regular_roll_price_htg": money(item.get("regular_roll_price_htg")), "roll_width": roll_width,
                    "min_width": min_width, "limit_length": bool(item.get("limit_length"))}
        if mode == "case":
            case_price = money(item.get("case_price_htg"))
            units = int(item.get("units_per_case") or 0)
            if case_price <= 0 or units < 2:
                return None
            return {**blank, "sale_mode": Product.CASE, "case_price_htg": case_price,
                    "regular_case_price_htg": money(item.get("regular_case_price_htg")), "units_per_case": units}
    except (TypeError, ValueError):
        return None
    return blank


@transaction.atomic
def legacy_publish(shop_key: str, payload: dict) -> dict:
    """The register's current publish call: settings plus the whole vitrine catalog."""
    digest = key_hash(shop_key)
    settings_in = payload.get("settings") if isinstance(payload.get("settings"), dict) else {}
    name = _text(payload.get("name"), 80)
    if not name:
        raise ApiError("Le nom de la boutique est requis.")
    slug = normalize_slug(str(payload.get("slug") or ""))
    shop = StorefrontShop.objects.select_for_update().filter(key_hash=digest).first()
    if not slug_available(slug, shop):
        raise ApiError("Ce lien est déjà pris. Choisissez-en un autre.", 409)
    if shop is None:
        if not settings.STOREFRONT_LEGACY_PUBLISH:
            raise ApiError("Clé de boutique inconnue.", 401)
        shop = StorefrontShop(business=_legacy_business(name), key_hash=digest, name=name)
    missing: list[str] = []
    data = {
        "slug": slug,
        "name": name,
        "phone": payload.get("phone"),
        "address": payload.get("address"),
        "city": payload.get("city") or settings_in.get("city"),
        "department": payload.get("department") or settings_in.get("department"),
        "categories": payload.get("categories") if payload.get("categories") is not None else settings_in.get("categories"),
        "description": settings_in.get("description"),
        "pickup_note": settings_in.get("pickup_note"),
        "cover": settings_in.get("cover"),
        "enabled": settings_in.get("enabled"),
        "paused": settings_in.get("paused"),
        "accept_when_closed": settings_in.get("accept_when_closed", True),
        "open_hour": settings_in.get("open_hour"),
        "close_hour": settings_in.get("close_hour"),
        "closed_weekdays": settings_in.get("closed_weekdays"),
        "usd_rate": payload.get("usd_rate"),
    }
    shop.published_at = timezone.now()
    apply_shop_settings(shop, data, missing)
    count = _upsert_legacy_products(shop.business, payload.get("products"), missing)
    sf_cache.invalidate_shop(shop.business_id)
    return {"slug": shop.slug, "published_at": _epoch(shop.published_at), "products": count,
            "missing_photos": missing}


def _upsert_legacy_products(business: Business, raw: object, missing: list[str]) -> int:
    items = [item for item in (raw if isinstance(raw, list) else [])[:MAX_PRODUCTS] if isinstance(item, dict)]
    existing = {p.external_id: p for p in Product.objects.filter(business=business, external_id__isnull=False)}
    categories = {c.name: c for c in Category.objects.filter(business=business)}
    seen: set[str] = set()
    to_create: list[Product] = []
    to_update: list[Product] = []
    options: dict[str, list] = {}
    for item in items:
        pid = _text(item.get("id"), 40)
        name = _text(item.get("name"), 120)
        price = money(item.get("price_htg"))
        sale = _sale_fields(item)
        if not pid or not name or price <= 0 or pid in seen or sale is None:
            continue
        seen.add(pid)
        cat_name = _text(item.get("category"), 60) or "Autres"
        if cat_name not in categories:
            categories[cat_name] = Category.objects.create(business=business, name=cat_name)
        try:
            stock = int(item.get("stock") or 0)
        except (TypeError, ValueError):
            stock = 0
        regular = money(item.get("regular_price_htg"))
        values = {
            "name": name,
            "category": categories[cat_name],
            "description": _text(item.get("description"), 600),
            "price_htg": price,
            "regular_price_htg": regular if regular > price else ZERO,
            "track_stock": bool(item.get("track_stock", True)),
            "stock_quantity": max(0, stock),
            "unit": _text(item.get("unit"), 12),
            "photo": _photo_name(item.get("photo"), missing),
            "is_active": True,
            "show_on_storefront": True,
            **sale,
        }
        product = existing.get(pid)
        if product is None:
            product = Product(business=business, external_id=pid, **values)
            to_create.append(product)
        else:
            for key, value in values.items():
                setattr(product, key, value)
            to_update.append(product)
        options[pid] = item.get("options") or []
    Product.objects.bulk_create(to_create, batch_size=500)
    if to_update:
        fields = ["name", "category", "description", "price_htg", "regular_price_htg", "track_stock",
                  "stock_quantity", "unit", "photo", "is_active", "show_on_storefront", "sale_mode",
                  "roll_price_htg", "regular_roll_price_htg", "roll_width", "min_width", "limit_length",
                  "case_price_htg", "regular_case_price_htg", "units_per_case", "updated_at"]
        now = timezone.now()
        for product in to_update:
            product.updated_at = now
        Product.objects.bulk_update(to_update, fields, batch_size=500)
    (Product.objects.filter(business=business, show_on_storefront=True)
     .exclude(external_id__in=seen).update(show_on_storefront=False, updated_at=timezone.now()))
    _replace_options(to_create + to_update, options)
    return len(seen)


def _replace_options(products: list[Product], options: dict[str, list]) -> None:
    ProductOptionGroup.objects.filter(product__in=products).delete()
    groups: list[ProductOptionGroup] = []
    choices: list[ProductOptionChoice] = []
    for product in products:
        for g_index, group in enumerate((options.get(product.external_id) or [])[:12]):
            if not isinstance(group, dict):
                continue
            gid, gname = _text(group.get("id"), 80), _text(group.get("name"), 60)
            raw_choices = [c for c in (group.get("choices") or [])[:30] if isinstance(c, dict)
                           and _text(c.get("id"), 80) and _text(c.get("name"), 60)]
            if not gid or not gname or not raw_choices:
                continue
            row = ProductOptionGroup(product=product, external_id=gid, name=gname, required=bool(group.get("required")),
                                     multiple=bool(group.get("multiple")), sort_order=g_index)
            groups.append(row)
            for c_index, choice in enumerate(raw_choices):
                choices.append(ProductOptionChoice(group=row, external_id=_text(choice.get("id"), 80),
                                                   name=_text(choice.get("name"), 60),
                                                   price_delta_htg=money(choice.get("delta_htg")), sort_order=c_index))
    ProductOptionGroup.objects.bulk_create(groups, batch_size=500)
    ProductOptionChoice.objects.bulk_create(choices, batch_size=1000)


# --- Public catalog ----------------------------------------------------------------------


def _vitrine_products(business_id):
    return (Product.objects.filter(business_id=business_id, show_on_storefront=True, is_active=True)
            .select_related("category")
            .prefetch_related(Prefetch("option_groups", queryset=ProductOptionGroup.objects.prefetch_related("choices")))
            .order_by("category__sort_order", "category__name", "name"))


def _sellable(product: Product) -> bool:
    if product.price_htg <= 0:
        return False
    if product.sale_mode == Product.ROLL:
        return product.roll_price_htg > 0 and product.roll_width >= 1 and 1 <= product.min_width <= product.roll_width
    if product.sale_mode == Product.CASE:
        return product.case_price_htg > 0 and product.units_per_case >= 2
    return True


def _product_card(p: Product) -> dict:
    stock = max(0, p.stock_quantity)
    regular = p.regular_price_htg if p.regular_price_htg > p.price_htg else ZERO
    return {
        "id": p.public_id,
        "name": p.name,
        "category": p.category.name if p.category else "Autres",
        "description": p.description,
        "price_htg": as_float(p.price_htg),
        "regular_price_htg": as_float(regular),
        "photo_url": public_image_url(p.photo),
        "available": (not p.track_stock) or stock > 0,
        "max_quantity": min(MAX_QTY, stock) if p.track_stock else MAX_QTY,
        "unit": p.unit,
        "options": [
            {"id": g.public_id, "name": g.name, "required": g.required, "multiple": g.multiple,
             "choices": [{"id": c.public_id, "name": c.name, "delta_htg": as_float(c.price_delta_htg)}
                         for c in g.choices.all()]}
            for g in p.option_groups.all() if g.choices.all()
        ],
        "track_stock": p.track_stock,
        "stock": stock,
        "sale_mode": p.sale_mode,
        "roll_price_htg": as_float(p.roll_price_htg),
        "regular_roll_price_htg": as_float(p.regular_roll_price_htg if p.regular_roll_price_htg > p.roll_price_htg else 0),
        "roll_width": p.roll_width,
        "min_width": p.min_width,
        "limit_length": p.limit_length,
        "case_price_htg": as_float(p.case_price_htg),
        "regular_case_price_htg": as_float(p.regular_case_price_htg if p.regular_case_price_htg > p.case_price_htg else 0),
        "units_per_case": p.units_per_case,
    }


def _catalog(shop: StorefrontShop) -> list[dict]:
    key = sf_cache.catalog_key(shop.business_id)
    products = cache.get(key)
    if products is None:
        products = [_product_card(p) for p in _vitrine_products(shop.business_id) if _sellable(p)]
        cache.set(key, products, sf_cache.CATALOG_TTL)
    return products


def _enabled_shop(raw_slug: str) -> StorefrontShop:
    slug = (raw_slug or "").strip().lower()
    shop = (StorefrontShop.objects.select_related("business__settings").filter(slug=slug, enabled=True).first()
            if slug else None)
    if shop is None:
        raise ApiError("Cette vitrine n'est pas disponible.", 404)
    return shop


def public_shop(raw_slug: str, now: datetime | None = None) -> dict:
    shop = _enabled_shop(raw_slug)
    products = _catalog(shop)
    categories: list[str] = []
    for product in products:
        if product["category"] not in categories:
            categories.append(product["category"])
    return {
        "slug": shop.slug,
        "name": shop.name,
        "phone": shop.phone,
        "address": shop.address,
        "city": shop.city,
        "department": shop.department,
        "business_categories": list(shop.categories or []),
        "description": shop.description,
        "pickup_note": shop.pickup_note,
        "cover_url": public_image_url(shop.cover),
        "usd_rate": float(shop.effective_rate()),
        "availability": availability(shop, now),
        "categories": categories,
        "products": products,
    }


def directory(department: str = "", now: datetime | None = None) -> dict:
    raw = _text(department, 40)
    wanted = clean_department(raw)
    shops = cache.get(sf_cache.DIRECTORY_KEY)
    if shops is None:
        shops = list(StorefrontShop.objects.filter(enabled=True, slug__isnull=False).order_by("name"))
        cache.set(sf_cache.DIRECTORY_KEY, shops, sf_cache.CATALOG_TTL)
    shops = sorted(shops, key=lambda s: s.name.lower())
    used: list[str] = []
    for shop in shops:
        for name in shop.categories or []:
            if name not in used:
                used.append(name)
    used.sort(key=lambda name: CATEGORY_ORDER.get(name, 10_000))
    if raw and not wanted:
        shops = []
    elif wanted:
        shops = [s for s in shops if s.department == wanted]
    results = []
    for shop in shops:
        info = availability(shop, now)
        results.append({"slug": shop.slug, "name": shop.name, "city": shop.city, "department": shop.department,
                        "categories": list(shop.categories or []), "description": shop.description,
                        "cover_url": public_image_url(shop.cover), "is_open_now": info["is_open_now"],
                        "paused": info["paused"], "opens_at_label": info["opens_at_label"]})
    return {"departments": list(DEPARTMENTS), "categories": used, "results": results}


# --- Requests ------------------------------------------------------------------------


def _product_index(business_id, ids: set[str]) -> dict[str, Product]:
    uuids = [i for i in ids if re.fullmatch(r"[0-9a-fA-F-]{36}", i)]
    qs = (Product.objects.filter(business_id=business_id, show_on_storefront=True, is_active=True)
          .prefetch_related("option_groups__choices"))
    from django.db.models import Q

    index: dict[str, Product] = {}
    for product in qs.filter(Q(external_id__in=ids) | Q(pk__in=uuids)):
        index[product.public_id] = product
        index[str(product.pk)] = product
    return index


def price_request_lines(shop: StorefrontShop, raw_lines: object) -> list[dict]:
    if not isinstance(raw_lines, list) or not raw_lines:
        raise ApiError("Le panier est vide.")
    raw_lines = [r for r in raw_lines[:MAX_LINES] if isinstance(r, dict)]
    index = _product_index(shop.business_id, {str(r.get("product_id") or "") for r in raw_lines})
    wanted: dict = {}
    lines: list[dict] = []
    for raw in raw_lines:
        product = index.get(str(raw.get("product_id") or ""))
        if product is None or not _sellable(product):
            raise ApiError("Un article n'est plus proposé. Actualisez la vitrine.", 409)
        priced = price_line(product, quantity=raw.get("quantity"), measure=raw.get("measure"), width=raw.get("width"),
                            choices=raw.get("choices"))
        wanted[product.pk] = wanted.get(product.pk, 0) + priced.stock_units
        if product.track_stock and wanted[product.pk] > product.stock_quantity:
            raise ApiError(stock_shortage_message(product), 409)
        lines.append({
            "product_id": product.public_id,
            "product_pk": str(product.pk),
            "name": product.name,
            "options": [{"group": o["group"], "id": o["id"], "name": o["name"]} for o in priced.options],
            "choices": [o["id"] for o in priced.options],
            "options_label": priced.options_label,
            "measure": priced.measure,
            "width": priced.width,
            "quantity": priced.quantity,
            "unit_htg": as_float(priced.unit_price),
            "total_htg": as_float(priced.line_total),
            "stock_units": priced.stock_units,
        })
    return lines


def _new_request_id() -> str:
    return secrets.token_urlsafe(18)


def _reserve(request: StorefrontRequest, *, allow_negative: bool = False) -> None:
    for line in request.lines:
        if line.get("product_pk") and line.get("stock_units"):
            adjust_stock(line["product_pk"], -int(line["stock_units"]), StockMovement.RESERVATION,
                         business=request.business, allow_negative=allow_negative, reference_type="storefront",
                         reference_id=request.number)
    request.stock_reserved = True
    request.reserved_until = timezone.now() + timedelta(minutes=settings.STOREFRONT_RESERVATION_MINUTES)


def _release(request: StorefrontRequest) -> None:
    for line in request.lines:
        if line.get("product_pk") and line.get("stock_units"):
            try:
                adjust_stock(line["product_pk"], int(line["stock_units"]), StockMovement.RELEASE,
                             business=request.business, reference_type="storefront", reference_id=request.number)
            except Product.DoesNotExist:
                continue
    request.stock_reserved = False
    request.reserved_until = None


def release_expired(limit: int = 200) -> int:
    """Give back stock held by unpaid commandes. Safe to run from cron or lazily."""
    ids = list(StorefrontRequest.objects.filter(status=StorefrontRequest.OPEN, stock_reserved=True,
                                                reserved_until__lt=timezone.now())
               .values_list("pk", flat=True)[:limit])
    released = 0
    for pk in ids:
        with transaction.atomic():
            request = (StorefrontRequest.objects.select_for_update().select_related("business")
                       .filter(pk=pk, status=StorefrontRequest.OPEN, stock_reserved=True).first())
            if request is None:
                continue
            _release(request)
            request.save(update_fields=["stock_reserved", "reserved_until", "updated_at"])
            released += 1
    return released


def _customer_fields(customer: object) -> dict:
    customer = customer if isinstance(customer, dict) else {}
    name = _text(customer.get("name"), 80)
    phone = _text(customer.get("phone"), 40)
    if not name:
        raise ApiError("Indiquez votre nom.")
    if len(re.sub(r"\D", "", phone)) < 8:
        raise ApiError("Indiquez un numéro de téléphone valide.")
    email = _text(customer.get("email"), 120)
    if email and not EMAIL_RE.match(email):
        raise ApiError("L'adresse e-mail n'est pas valide.")
    return {"customer_name": name, "customer_phone": phone, "customer_email": email}


@transaction.atomic
def create_request(raw_slug: str, payload: dict, *, account: ShopperAccount | None = None,
                   now: datetime | None = None) -> StorefrontRequest:
    kind = str(payload.get("kind") or "")
    if kind not in dict(StorefrontRequest.KINDS):
        raise ApiError("Choisissez devis ou commande.")
    shop = _enabled_shop(raw_slug)
    avail = availability(shop, now)
    if kind == StorefrontRequest.COMMANDE and not avail["accepts_orders"]:
        if avail["paused"]:
            raise ApiError("La boutique a mis les commandes en pause.", 409)
        raise ApiError("La boutique est fermée pour le moment.", 409)
    if kind == StorefrontRequest.DEVIS and not avail["accepts_quotes"]:
        raise ApiError("La boutique n'accepte pas de demandes pour le moment.", 409)
    customer = _customer_fields(payload.get("customer"))
    lines = price_request_lines(shop, payload.get("lines"))
    total = money(sum((Decimal(str(line["total_htg"])) for line in lines), ZERO))
    mode = str(payload.get("fulfillment_mode") or "inStore")
    if mode not in ("inStore", "pickup", "delivery"):
        mode = "inStore"
    request = StorefrontRequest(
        id=_new_request_id(),
        shop=shop,
        business=shop.business,
        number=next_number(shop.business, "DEV" if kind == StorefrontRequest.DEVIS else "CMD"),
        kind=kind,
        source="storefront",
        account=account,
        note=_text(payload.get("note"), 500),
        fulfillment_mode=mode,
        delivery_location=_text(payload.get("delivery_location"), 300) if mode == "delivery" else "",
        lines=lines,
        total_htg=total,
        usd_rate=shop.effective_rate(),
        **customer,
    )
    if kind == StorefrontRequest.COMMANDE:
        _reserve(request)
    request.save(force_insert=True)
    if kind == StorefrontRequest.DEVIS:
        _attach_quote(request)
    return request


def _attach_quote(request: StorefrontRequest) -> None:
    from apps.notifications.services import notify
    from apps.sales.models import OrderSource, Quote, QuoteLine

    quote = Quote.objects.create(
        business=request.business, number=request.number, source=OrderSource.STOREFRONT,
        client_name=request.customer_name, client_phone=request.customer_phone, client_email=request.customer_email,
        subtotal_htg=request.total_htg + request.discount_htg, total_htg=request.total_htg, note=request.note,
        created_by_name="Vitrine",
    )
    QuoteLine.objects.bulk_create([
        QuoteLine(quote=quote, product_id=line.get("product_pk") or None, product_name=line["name"],
                  options_label=line.get("options_label", "")[:300], choices=line.get("choices", []),
                  measure=line.get("measure", ""), width=line.get("width", 0), quantity=line["quantity"],
                  unit_price_htg=money(line["unit_htg"]), line_total_htg=money(line["total_htg"]), sort_order=index)
        for index, line in enumerate(request.lines)
    ])
    request.quote = quote
    request.save(update_fields=["quote", "updated_at"])
    notify(request.business, "storefront_quote", "Nouveau devis reçu",
           f"{request.number} — {request.customer_name}", request_id=request.pk)


@transaction.atomic
def create_shop_request(shop: StorefrontShop, payload: dict) -> StorefrontRequest:
    """A devis or commande prepared at the register to share by link. The
    shop sets its own prices (discounts, negotiated quotes), so lines are
    taken as sent once the caller is verified."""
    kind = str(payload.get("kind") or "devis")
    if kind not in dict(StorefrontRequest.KINDS):
        raise ApiError("Type de demande inconnu.")
    if not shop.slug:
        raise ApiError("Publiez d'abord la vitrine pour partager un lien.", 409)
    raw_lines = [r for r in (payload.get("lines") or [])[:MAX_LINES] if isinstance(r, dict)]
    index = _product_index(shop.business_id, {str(r.get("product_id") or "") for r in raw_lines})
    lines = []
    for raw in raw_lines:
        try:
            qty = int(raw.get("quantity") or 0)
        except (TypeError, ValueError):
            qty = 0
        unit = money(raw.get("unit_htg"))
        name = _text(raw.get("name"), 120)
        if qty < 1 or qty > MAX_QTY or unit <= 0 or not name:
            continue
        product = index.get(str(raw.get("product_id") or ""))
        lines.append({
            "product_id": _text(raw.get("product_id"), 40),
            "product_pk": str(product.pk) if product else "",
            "name": name,
            "options": [],
            "choices": [],
            "options_label": _text(raw.get("options_label"), 200),
            "measure": "",
            "width": 0,
            "quantity": qty,
            "unit_htg": as_float(unit),
            "total_htg": as_float(unit * qty),
            "stock_units": qty if product and product.sale_mode == Product.PIECE else 0,
        })
    if not lines:
        raise ApiError("Ajoutez au moins un article.")
    subtotal = money(sum((Decimal(str(line["total_htg"])) for line in lines), ZERO))
    discount = min(money(payload.get("discount_htg")), subtotal)
    external = _text(payload.get("reference"), 40)
    customer = payload.get("customer") if isinstance(payload.get("customer"), dict) else {}
    if external:
        existing = StorefrontRequest.objects.select_for_update().filter(shop=shop, external_ref=external).first()
        if existing is not None:
            if existing.status == StorefrontRequest.OPEN:
                existing.lines = lines
                existing.discount_htg = discount
                existing.total_htg = money(subtotal - discount)
                existing.usd_rate = shop.effective_rate()
                existing.save()
            return existing
    return StorefrontRequest.objects.create(
        id=_new_request_id(),
        shop=shop,
        business=shop.business,
        number=_text(payload.get("number"), 30) or next_number(shop.business, "DEV" if kind == "devis" else "CMD"),
        kind=kind,
        source="pos",
        customer_name=_text(customer.get("name"), 80),
        customer_phone=_text(customer.get("phone"), 40),
        customer_email=_text(customer.get("email"), 120),
        note=_text(payload.get("note"), 500),
        lines=lines,
        discount_htg=discount,
        total_htg=money(subtotal - discount),
        usd_rate=shop.effective_rate(),
        external_ref=external,
    )


def get_request(request_id: str) -> StorefrontRequest:
    if not REQUEST_ID_RE.match(request_id or ""):
        raise ApiError("Ce lien n'existe pas ou a expiré.", 404)
    request = (StorefrontRequest.objects.select_related("shop", "business__settings", "order")
               .filter(pk=request_id).first())
    if request is None:
        raise ApiError("Ce lien n'existe pas ou a expiré.", 404)
    return request


def _payable(request_id: str) -> StorefrontRequest:
    """Locks the request and makes sure its stock is held before charging."""
    with transaction.atomic():
        request = StorefrontRequest.objects.select_for_update().select_related("business", "shop").get(
            pk=get_request(request_id).pk)
        if request.status == StorefrontRequest.PAID:
            raise ApiError("Cette demande est déjà payée.", 409)
        if request.status != StorefrontRequest.OPEN:
            raise ApiError("Cette demande n'est plus disponible.", 409)
        if request.total_htg <= 0:
            raise ApiError("Le montant doit être supérieur à zéro.")
        if request.kind == StorefrontRequest.COMMANDE and request.source == "storefront":
            if not request.stock_reserved:
                _reserve(request)
            else:
                request.reserved_until = timezone.now() + timedelta(minutes=settings.STOREFRONT_RESERVATION_MINUTES)
            request.save(update_fields=["stock_reserved", "reserved_until", "updated_at"])
        return request


def order_usd_cents(request: StorefrontRequest) -> int:
    return htg_to_usd_cents(request.total_htg, request.usd_rate)


def moncash_amount(request: StorefrontRequest) -> int:
    return whole_htg(request.total_htg)


def card_intent(request_id: str) -> dict:
    from apps.payments.providers import stripe

    request = _payable(request_id)
    intent = stripe.create_payment_intent(
        reference=request.pk,
        order_usd_cents=order_usd_cents(request),
        description=f"{request.shop.name or 'Boutique'} · {request.number}",
        kind="storefront",
        metadata={"business": str(request.business_id)},
    )
    StorefrontRequest.objects.filter(pk=request.pk).update(card_intent_id=intent["id"], updated_at=timezone.now())
    return {**intent, "publishable_key": settings.STRIPE_PUBLISHABLE_KEY}


def settle_card_intent(request_id: str, intent: dict) -> bool:
    """Mark paid only when Stripe reports success for this request's amount."""
    from apps.payments.providers import stripe
    from apps.payments.providers.errors import PaymentError

    request = get_request(request_id)
    if request.status == StorefrontRequest.PAID:
        return True
    metadata = intent.get("metadata") or {}
    expected = stripe.price_card_charge(order_usd_cents(request))["total_usd_cents"]
    if str(metadata.get("reference") or "") != request.pk:
        raise PaymentError(400, "Ce paiement ne correspond pas à la demande.")
    if str(intent.get("status") or "") != "succeeded":
        raise PaymentError(402, "Le paiement par carte n'est pas confirmé.")
    received = int(intent.get("amount_received") or intent.get("amount") or 0)
    if received < expected:
        raise PaymentError(402, "Le montant reçu ne correspond pas au total.")
    mark_paid(request.pk, method="card", reference=str(intent.get("id") or ""), amount=received, currency="usd")
    return True


def card_confirm(request_id: str, intent_id: str) -> StorefrontRequest:
    from apps.payments.providers import stripe

    request = get_request(request_id)
    if request.status != StorefrontRequest.PAID:
        settle_card_intent(request_id, stripe.fetch_payment_intent(intent_id))
    return get_request(request_id)


def moncash_start(request_id: str) -> dict:
    from apps.payments.providers import moncash

    request = _payable(request_id)
    result = moncash.create_payment(request.pk, moncash_amount(request))
    StorefrontRequest.objects.filter(pk=request.pk).update(moncash_order_id=result["order_id"], updated_at=timezone.now())
    return result


def moncash_check(request_id: str) -> dict:
    from apps.payments.providers import moncash
    from apps.payments.providers.errors import PaymentError

    request = get_request(request_id)
    if request.status == StorefrontRequest.PAID or not request.moncash_order_id:
        return {"paid": request.status == StorefrontRequest.PAID, "request": public_view(request)}
    status = moncash.payment_status(request.moncash_order_id)
    if not status["paid"]:
        return {"paid": False, "request": public_view(request)}
    amount = moncash_amount(request)
    if status["cost_htg"] and status["cost_htg"] < amount:
        raise PaymentError(402, "Le montant MonCash reçu ne correspond pas au total.")
    mark_paid(request.pk, method="moncash", reference=status["transaction_id"] or request.moncash_order_id,
              amount=status["cost_htg"] or amount, currency="htg")
    return {"paid": True, "request": public_view(get_request(request_id))}


def _find_customer(request: StorefrontRequest):
    from apps.customers.models import Customer, phone_digits

    digits = phone_digits(request.customer_phone)
    if len(digits) < 8:
        return None
    customer = Customer.objects.filter(business=request.business, phone_digits=digits).first()
    if customer is None:
        customer = Customer.objects.create(business=request.business, name=request.customer_name or "Client vitrine",
                                           phone=request.customer_phone, email=request.customer_email)
    return customer


@transaction.atomic
def mark_paid(request_id: str, *, method: str, reference: str, amount: int, currency: str) -> StorefrontRequest:
    request = StorefrontRequest.objects.select_for_update().select_related("business__settings", "shop").get(pk=request_id)
    if request.status == StorefrontRequest.PAID:
        return request
    request.status = StorefrontRequest.PAID
    request.paid_at = timezone.now()
    request.payment_method = method[:10]
    request.payment_reference = reference[:120]
    request.payment_amount = int(amount)
    request.payment_currency = currency[:3]
    request.order = _create_order(request)
    request.stock_reserved = False
    request.reserved_until = None
    request.save()
    if request.quote_id:
        from apps.sales.models import Quote, QuoteStatus

        Quote.objects.filter(pk=request.quote_id).update(status=QuoteStatus.CONVERTED, converted_order=request.order,
                                                         updated_at=timezone.now())
    from apps.notifications.services import notify

    notify(request.business, "storefront_order_paid", "Commande en ligne payée",
           f"{request.number} — {request.customer_name} : {request.total_htg} HTG", request_id=request.pk,
           order_id=str(request.order_id) if request.order_id else "")
    audit(request.business, "storefront.paid", target=request.order, request=None, method=method,
          number=request.number)
    return request


def _create_order(request: StorefrontRequest):
    """The paid request becomes a POS order. Reserved stock turns into a sale."""
    from apps.sales.models import OrderSource
    from apps.sales.services import create_sale

    actor = SystemActor(request.business, "Vitrine")
    location = Location.objects.filter(business=request.business, is_active=True).order_by("-is_default", "created_at").first()
    customer = _find_customer(request)
    method = "moncash" if request.payment_method == "moncash" else "card"
    base = {
        "client_name": request.customer_name,
        "client_phone": request.customer_phone,
        "client_email": request.customer_email,
        "customer_id": str(customer.pk) if customer else None,
        "fulfillment_mode": "inStore" if request.fulfillment_mode == "delivery" and not request.business.settings.delivery_enabled else request.fulfillment_mode,
        "delivery_location": request.delivery_location,
        "discount_htg": request.discount_htg,
        "note": f"Vitrine {request.number}" + (f" — {request.note}" if request.note else ""),
        "payments": [{"method": method, "amount_htg": request.total_htg, "reference": request.payment_reference[:120]}],
    }
    if base["fulfillment_mode"] == "delivery" and not base["delivery_location"]:
        base["fulfillment_mode"] = "inStore"
    product_lines = [
        {"product_id": line.get("product_pk") or None, "name": line["name"], "quantity": line["quantity"],
         "measure": line.get("measure", ""), "width": line.get("width", 0), "choices": line.get("choices", []),
         "unit_price_htg": line["unit_htg"]}
        for line in request.lines
    ]
    kwargs = dict(location=location, source=OrderSource.STOREFRONT, discount_preapproved=True, apply_fees=False,
                  record_cash=False)
    try:
        with transaction.atomic():
            if request.stock_reserved:
                _release(request)
            order, _ = create_sale(actor, base | {"lines": product_lines}, **kwargs)
            return order
    except ApiError as exc:
        # The catalog changed after the shopper paid. The money is in, so the
        # order is recorded with the paid lines as written; stock stays as reserved.
        log.warning("Vitrine %s: order recorded without catalog lines (%s)", request.number, exc.message)
    free_lines = [
        {"product_id": None, "name": f"{line['name']} ({line['options_label']})" if line.get("options_label") else line["name"],
         "quantity": line["quantity"], "unit_price_htg": line["unit_htg"]}
        for line in request.lines
    ]
    order, _ = create_sale(actor, base | {"lines": free_lines}, **kwargs)
    return order


def cancel_request(request: StorefrontRequest, actor) -> StorefrontRequest:
    with transaction.atomic():
        request = StorefrontRequest.objects.select_for_update().select_related("business").get(pk=request.pk)
        if request.status != StorefrontRequest.OPEN:
            raise ApiError("Cette demande ne peut plus être annulée.", 409)
        if request.stock_reserved:
            _release(request)
        request.status = StorefrontRequest.CANCELLED
        request.save()
    audit(request.business, "storefront.cancelled", actor=actor, number=request.number)
    return request


# --- Views -------------------------------------------------------------------------------

ORDER_STATUS_LABEL = {
    "paid": "Payée", "ready": "Prête", "pickedUp": "Retirée", "delivered": "Livrée", "completed": "Terminée",
    "cancelled": "Annulée", "refunded": "Remboursée", "partiallyPaid": "Partiellement payée",
    "checkPending": "Chèque en attente",
}


def public_view(request: StorefrontRequest) -> dict:
    shop = request.shop
    rate = float(request.usd_rate or shop.effective_rate())
    order_status = request.order.status if request.order_id else ""
    return {
        "id": request.pk,
        "number": request.number,
        "kind": request.kind,
        "status": request.status,
        "created_at": _epoch(request.created_at),
        "paid_at": _epoch(request.paid_at),
        "payment_method": request.payment_method,
        "customer_name": request.customer_name,
        "note": request.note,
        "lines": [{"name": l["name"], "options_label": l.get("options_label", ""), "quantity": l["quantity"],
                   "unit_htg": l["unit_htg"], "total_htg": l["total_htg"],
                   "stock_units": l.get("stock_units", l["quantity"])} for l in request.lines],
        "discount_htg": as_float(request.discount_htg),
        "total_htg": as_float(request.total_htg),
        "usd_rate": rate,
        "order_usd_cents": order_usd_cents(request),
        "moncash_htg": moncash_amount(request),
        "reserved_until": _epoch(request.reserved_until),
        "order_status": order_status,
        "order_status_label": ORDER_STATUS_LABEL.get(order_status, ""),
        "shop": {"slug": shop.slug or "", "name": shop.name, "phone": shop.phone, "pickup_note": shop.pickup_note,
                 "cover_url": public_image_url(shop.cover)},
    }


def shop_view(request: StorefrontRequest) -> dict:
    view = public_view(request)
    view.pop("shop", None)
    view["customer"] = {"name": request.customer_name, "phone": request.customer_phone, "email": request.customer_email}
    view["source"] = request.source
    view["external_ref"] = request.external_ref
    view["payment"] = ({"method": request.payment_method, "reference": request.payment_reference,
                        "amount": request.payment_amount, "currency": request.payment_currency}
                       if request.paid_at else {})
    view["order_id"] = str(request.order_id) if request.order_id else ""
    view["order_number"] = request.order.number if request.order_id else ""
    view["quote_id"] = str(request.quote_id) if request.quote_id else ""
    view["lines"] = [{"product_id": l.get("product_id", ""), "name": l["name"],
                      "options_label": l.get("options_label", ""), "quantity": l["quantity"],
                      "unit_htg": l["unit_htg"], "total_htg": l["total_htg"],
                      "stock_units": l.get("stock_units", l["quantity"])} for l in request.lines]
    return view


def inbox(shop: StorefrontShop, limit: int = 300) -> list[dict]:
    rows = (StorefrontRequest.objects.filter(shop=shop).select_related("shop", "order")
            .order_by("-created_at")[:limit])
    return [shop_view(r) for r in rows]


# --- Shopper accounts ----------------------------------------------------------------------


def account_view(account: ShopperAccount) -> dict:
    return {"name": account.name, "phone": account.phone, "country": account.country, "email": account.email}


def _issue_shopper_session(account: ShopperAccount) -> str:
    raw = new_token()
    ShopperSession.objects.create(account=account, token_hash=hash_token(raw),
                                  expires_at=timezone.now() + timedelta(days=settings.SHOPPER_SESSION_DAYS))
    return raw


def account_for_token(token: str, *, required: bool = True) -> ShopperAccount | None:
    token = (token or "").strip()
    session = (ShopperSession.objects.select_related("account").filter(token_hash=hash_token(token)).first()
               if token else None)
    if session is None or not session.is_valid():
        if required:
            raise ApiError("Connexion requise.", 401)
        return None
    return session.account


def request_code(phone, country) -> dict:
    return send_code(phone, country)


def verify_code(phone, country, code) -> dict:
    iso, e164, digits = check_code(phone, country, code)
    account = ShopperAccount.objects.filter(phone_digits=digits).first()
    if account is not None and account.name:
        if not account.country:
            account.country = iso
            account.save(update_fields=["country", "updated_at"])
        return {"registered": True, "token": _issue_shopper_session(account), "account": account_view(account)}
    raw = new_token()
    ShopperSignup.objects.filter(phone_digits=digits).delete()
    ShopperSignup.objects.create(token_hash=hash_token(raw), phone_digits=digits, phone=e164, country=iso,
                                 expires_at=timezone.now() + timedelta(minutes=SIGNUP_MINUTES))
    return {"registered": False, "signup_token": raw}


@transaction.atomic
def register_account(signup_token, name, email="") -> dict:
    display = _text(name, 80)
    if len(display) < 2:
        raise ApiError("Indiquez votre nom complet.")
    mail = clean_email(email)
    signup = ShopperSignup.objects.select_for_update().filter(token_hash=hash_token(str(signup_token or ""))).first()
    if signup is None or signup.expires_at < timezone.now():
        if signup is not None:
            signup.delete()
        raise ApiError("Cette étape a expiré. Recommencez avec votre numéro.", 401)
    account, _ = ShopperAccount.objects.get_or_create(phone_digits=signup.phone_digits,
                                                      defaults={"phone": signup.phone, "name": display})
    account.phone = signup.phone
    account.country = signup.country
    account.name = display
    account.email = mail
    account.save()
    signup.delete()
    return {"token": _issue_shopper_session(account), "account": account_view(account)}


def _pin_hash(digits: str, pin: str) -> str:
    return hmac.new(settings.PIN_PEPPER.encode(), f"shopper:{digits}:{pin}".encode(), "sha256").hexdigest()


def open_account(phone, pin, name="") -> dict:
    """Legacy sign-in with a personal code, kept for the current vitrine build."""
    digits = re.sub(r"\D", "", str(phone or ""))
    if len(digits) < 8:
        raise ApiError("Indiquez un numéro de téléphone valide.")
    code = str(pin or "").strip()
    if not re.fullmatch(r"\d{4,6}", code):
        raise ApiError("Le code personnel doit avoir 4 à 6 chiffres.")
    account = ShopperAccount.objects.filter(phone_digits=digits).first()
    display = _text(name, 80)
    if account is None:
        if not display:
            raise ApiError("Indiquez votre nom pour créer le compte.")
        account = ShopperAccount.objects.create(phone_digits=digits, phone=_text(phone, 40) or digits, name=display,
                                                pin_hash=_pin_hash(digits, code))
    elif not account.pin_hash or not hmac.compare_digest(account.pin_hash, _pin_hash(digits, code)):
        raise ApiError("Code personnel incorrect.", 401)
    elif display:
        account.name = display
        account.save(update_fields=["name", "updated_at"])
    return {"token": _issue_shopper_session(account), "account": account_view(account)}


def update_account(account: ShopperAccount, name) -> dict:
    display = _text(name, 80)
    if not display:
        raise ApiError("Indiquez votre nom.")
    account.name = display
    account.save(update_fields=["name", "updated_at"])
    return account_view(account)


def account_orders(account: ShopperAccount) -> list[dict]:
    rows = (StorefrontRequest.objects.filter(account=account).select_related("shop", "order")
            .order_by("-created_at")[:200])
    return [{
        "id": r.pk, "number": r.number, "kind": r.kind, "status": r.status, "created_at": _epoch(r.created_at),
        "shop_name": r.shop.name, "shop_slug": r.shop.slug or "", "total_htg": as_float(r.total_htg),
        "usd_rate": float(r.usd_rate), "order_status": r.order.status if r.order_id else "",
    } for r in rows]

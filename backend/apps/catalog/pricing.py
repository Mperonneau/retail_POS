"""Server-side line pricing shared by the register and the vitrine.

Ported from the vitrine server so both apps price a roll, a case or an
option exactly the same way. Messages stay in French; the apps show them.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal

from apps.common.exceptions import ApiError
from apps.common.money import money

from .models import Product

MAX_QTY = 999
MAX_WIDTH = 10000


@dataclass
class PricedLine:
    product: Product
    quantity: int
    unit_price: Decimal
    stock_units_each: int
    measure: str
    width: int
    measure_label: str
    options: list[dict] = field(default_factory=list)

    @property
    def options_label(self) -> str:
        parts = [self.measure_label] if self.measure_label else []
        parts.extend(choice["name"] for choice in self.options)
        return ", ".join(parts)

    @property
    def line_total(self) -> Decimal:
        return money(self.unit_price * self.quantity)

    @property
    def stock_units(self) -> int:
        return self.stock_units_each * self.quantity


def parse_quantity(raw: object) -> int:
    try:
        qty = int(raw or 0)
    except (TypeError, ValueError):
        qty = 0
    if qty < 1 or qty > MAX_QTY:
        raise ApiError("Quantité invalide.")
    return qty


def measured_price(product: Product, measure: str, width_raw: object) -> tuple[Decimal, int, str, int]:
    """(unit price, stock taken by one quantity, label, width) for a sale measure."""
    mode = product.sale_mode or Product.PIECE
    measure = str(measure or "")
    name = product.name
    try:
        width = int(float(width_raw or 0))
    except (TypeError, ValueError):
        width = 0
    if mode == Product.ROLL:
        if measure == "roll":
            return money(product.roll_price_htg), int(product.roll_width), "Longueur entière", 0
        if measure == "cut":
            minimum = int(product.min_width)
            maximum = int(product.roll_width or 0)
            if width < max(1, minimum):
                raise ApiError(f"La longueur minimum pour {name} est {minimum} po.")
            if product.limit_length and maximum >= 1 and width > maximum:
                raise ApiError(f"La longueur maximum pour {name} est {maximum} po.")
            if width > MAX_WIDTH:
                raise ApiError("Cette longueur est trop grande.")
            return money(product.price_htg * width), width, f"{width} po", width
        raise ApiError(f"Choisissez la longueur entière ou une longueur pour {name}.")
    if mode == Product.CASE:
        if measure == "case":
            count = int(product.units_per_case)
            return money(product.case_price_htg), count, f"Caisse de {count}", 0
        if measure in ("", "unit"):
            return money(product.price_htg), 1, "À l'unité", 0
        raise ApiError(f"Choisissez une caisse ou une unité pour {name}.")
    return money(product.price_htg), 1, "", 0


def resolve_options(product: Product, picked_ids: object) -> tuple[list[dict], Decimal]:
    """Validate chosen option ids (public ids or UUIDs) against the product."""
    picked = {str(c) for c in (picked_ids or []) if c} if isinstance(picked_ids, (list, tuple)) else set()
    chosen: list[dict] = []
    extra = Decimal("0")
    for group in product.option_groups.all():
        in_group = [c for c in group.choices.all() if c.public_id in picked or str(c.pk) in picked]
        if group.required and not in_group:
            raise ApiError(f"Choisissez « {group.name} » pour {product.name}.")
        if not group.multiple and len(in_group) > 1:
            raise ApiError(f"Une seule option « {group.name} » est possible.")
        for choice in in_group:
            chosen.append({"group": group.name, "id": choice.public_id, "name": choice.name,
                           "delta_htg": float(choice.price_delta_htg)})
            extra += choice.price_delta_htg
    return chosen, money(extra)


def price_line(product: Product, *, quantity: object, measure: object = "", width: object = 0,
               choices: object = None) -> PricedLine:
    qty = parse_quantity(quantity)
    base, each, label, cut_width = measured_price(product, str(measure or ""), width)
    options, extra = resolve_options(product, choices)
    return PricedLine(
        product=product,
        quantity=qty,
        unit_price=money(base + extra),
        stock_units_each=max(1, each),
        measure=str(measure or ""),
        width=cut_width,
        measure_label=label,
        options=options,
    )


def stock_shortage_message(product: Product) -> str:
    if product.stock_quantity <= 0:
        return f"{product.name} est en rupture de stock."
    if product.sale_mode == Product.ROLL:
        return f"Il reste {product.stock_quantity} po de {product.name}."
    if product.sale_mode == Product.CASE:
        return f"Il reste {product.stock_quantity} unités de {product.name}."
    return f"Il reste {product.stock_quantity} × {product.name} en stock."

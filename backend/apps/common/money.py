from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

CENT = Decimal("0.01")
ZERO = Decimal("0.00")
# Amounts below this are rounding noise (same tolerance as the register).
EPSILON = Decimal("0.009")


def money(value: object) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    else:
        try:
            amount = Decimal(str(value if value not in (None, "") else 0))
        except (InvalidOperation, ValueError):
            amount = ZERO
    if not amount.is_finite():
        return ZERO
    return amount.quantize(CENT, rounding=ROUND_HALF_UP)


def positive_money(value: object) -> Decimal:
    amount = money(value)
    return amount if amount > 0 else ZERO


def percent_of(amount: Decimal, percent: object) -> Decimal:
    return money(money(amount) * money(percent) / Decimal(100))


def htg_to_usd_cents(amount_htg: object, rate: object) -> int:
    amount = money(amount_htg)
    rate_value = Decimal(str(rate or 0))
    if amount <= 0 or rate_value <= 0:
        return 0
    return int((amount / rate_value * 100).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def whole_htg(amount_htg: object) -> int:
    return int(money(amount_htg).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def as_float(value: object) -> float:
    return float(money(value))

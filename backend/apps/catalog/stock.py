from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from apps.accounts.models import StaffMember
from apps.common.exceptions import ApiError

from .models import Product, StockMovement
from .pricing import stock_shortage_message


def adjust_stock(
    product_id,
    delta: int,
    kind: str,
    *,
    business,
    actor=None,
    allow_negative: bool = True,
    reference_type: str = "",
    reference_id: str = "",
    note: str = "",
    supplier=None,
    supplier_name: str = "",
    purchase_order=None,
    unit_cost: Decimal | None = None,
    received_at=None,
) -> StockMovement | None:
    """Change stock under a row lock and write the movement.

    Untracked products only get a movement when it is an explicit adjustment.
    """
    with transaction.atomic():
        product = Product.objects.select_for_update().get(pk=product_id, business=business)
        if not product.track_stock and kind in (StockMovement.SALE, StockMovement.RESERVATION, StockMovement.RELEASE,
                                                StockMovement.RETURN):
            return None
        before = product.stock_quantity
        after = before + int(delta)
        if after < 0 and not allow_negative and delta < 0:
            raise ApiError(stock_shortage_message(product), 409)
        product.stock_quantity = after
        fields = ["stock_quantity", "updated_at"]
        if unit_cost is not None and unit_cost > 0 and delta > 0:
            product.cost_htg = unit_cost
            fields.append("cost_htg")
        product.save(update_fields=fields)
        movement = StockMovement.objects.create(
            business=business,
            product=product,
            kind=kind,
            quantity_delta=int(delta),
            stock_after=after,
            received_at=received_at or timezone.now(),
            supplier=supplier,
            supplier_name=supplier_name or (supplier.name if supplier else ""),
            purchase_order=purchase_order,
            reference_type=reference_type,
            reference_id=str(reference_id or ""),
            note=note[:300],
            unit_cost_htg=unit_cost,
            recorded_by=actor if isinstance(actor, StaffMember) else None,
        )
    if product.track_stock and before > product.min_stock >= after:
        from apps.notifications.services import notify

        notify(
            business,
            "low_stock",
            "Stock bas",
            f"{product.name} : il reste {after} {product.stock_unit or ''}".strip(),
            product_id=str(product.pk),
        )
    return movement

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from apps.common.audit import audit
from apps.common.exceptions import ApiError

from .models import Product, PurchaseOrder, StockMovement
from .stock import adjust_stock


def record_initial_stock(product: Product, actor) -> None:
    if product.track_stock and product.stock_quantity:
        StockMovement.objects.create(
            business=product.business,
            product=product,
            kind=StockMovement.STOCK_IN,
            quantity_delta=product.stock_quantity,
            stock_after=product.stock_quantity,
            note="Stock initial",
            recorded_by=actor,
        )


def manual_stock_change(product: Product, *, kind: str, quantity: int, actor, note: str = "", supplier=None,
                        supplier_name: str = "", unit_cost=None, received_at=None) -> StockMovement:
    """Entrée (positive quantity) or ajustement (signed) from the inventory panel."""
    if kind not in (StockMovement.STOCK_IN, StockMovement.ADJUSTMENT):
        raise ApiError("Type de mouvement inconnu.")
    if kind == StockMovement.STOCK_IN and quantity <= 0:
        raise ApiError("La quantité reçue doit être positive.")
    if quantity == 0:
        raise ApiError("La quantité ne peut pas être zéro.")
    movement = adjust_stock(
        product.pk,
        quantity,
        kind,
        business=product.business,
        actor=actor,
        note=note,
        supplier=supplier,
        supplier_name=supplier_name,
        unit_cost=unit_cost,
        received_at=received_at,
    )
    audit(product.business, f"stock.{kind}", actor=actor, target=product, quantity=quantity)
    return movement


@transaction.atomic
def send_purchase_order(po: PurchaseOrder, actor) -> PurchaseOrder:
    if po.status != PurchaseOrder.DRAFT:
        raise ApiError("Ce bon de commande a déjà été envoyé.")
    po.status = PurchaseOrder.SENT
    po.sent_at = timezone.now()
    po.save(update_fields=["status", "sent_at", "updated_at"])
    audit(po.business, "po.sent", actor=actor, target=po)
    return po


@transaction.atomic
def receive_purchase_order(po: PurchaseOrder, receipts: list[dict], actor) -> PurchaseOrder:
    """receipts: [{"line": <uuid>, "quantity": int}]. Unknown lines are rejected."""
    po = PurchaseOrder.objects.select_for_update().get(pk=po.pk)
    if po.status not in (PurchaseOrder.SENT, PurchaseOrder.PARTIAL, PurchaseOrder.DRAFT):
        raise ApiError("Ce bon de commande ne peut plus être réceptionné.")
    lines = {str(line.pk): line for line in po.lines.select_related("product")}
    if not receipts:
        raise ApiError("Indiquez les quantités reçues.")
    for receipt in receipts:
        line = lines.get(str(receipt.get("line")))
        if line is None:
            raise ApiError("Ligne inconnue sur ce bon de commande.")
        try:
            qty = int(receipt.get("quantity") or 0)
        except (TypeError, ValueError):
            qty = 0
        if qty < 1:
            continue
        if qty > line.remaining:
            raise ApiError(f"{line.product_name} : il reste seulement {line.remaining} à recevoir.")
        line.quantity_received += qty
        line.save(update_fields=["quantity_received", "updated_at"])
        if line.product_id:
            adjust_stock(
                line.product_id,
                qty,
                StockMovement.PO_RECEIPT,
                business=po.business,
                actor=actor,
                supplier=po.supplier,
                purchase_order=po,
                unit_cost=line.unit_cost_htg,
                reference_type="purchase_order",
                reference_id=str(po.pk),
            )
    all_lines = list(po.lines.all())
    if all(line.remaining == 0 for line in all_lines):
        po.status = PurchaseOrder.RECEIVED
        po.received_at = timezone.now()
    elif any(line.quantity_received for line in all_lines):
        po.status = PurchaseOrder.PARTIAL
    po.save(update_fields=["status", "received_at", "updated_at"])
    audit(po.business, "po.received", actor=actor, target=po, status=po.status)
    return po


def cancel_purchase_order(po: PurchaseOrder, actor) -> PurchaseOrder:
    if po.status in (PurchaseOrder.RECEIVED, PurchaseOrder.CANCELLED):
        raise ApiError("Ce bon de commande ne peut plus être annulé.")
    po.status = PurchaseOrder.CANCELLED
    po.save(update_fields=["status", "updated_at"])
    audit(po.business, "po.cancelled", actor=actor, target=po)
    return po

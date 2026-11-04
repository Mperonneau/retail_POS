"""Client account (A/R) and store-credit ledgers.

Each posting locks the customer row, writes the entry with its running
balance and updates the cached balance in one transaction.
"""

from __future__ import annotations

from decimal import Decimal

from django.db import transaction

from apps.accounts import roles
from apps.common.audit import audit
from apps.common.exceptions import ApiError
from apps.common.money import EPSILON, ZERO, money
from apps.common.numbering import next_number

from .models import Customer, CustomerTransaction, StoreCreditEntry


def _actor_fields(actor) -> dict:
    from apps.accounts.models import StaffMember

    if isinstance(actor, StaffMember):
        return {"recorded_by": actor, "recorded_by_name": actor.full_name}
    return {"recorded_by": None, "recorded_by_name": str(actor or "Système")[:120]}


def _lock(customer: Customer) -> Customer:
    return Customer.objects.select_for_update().get(pk=customer.pk)


def ensure_credit_allowed(customer: Customer, amount: Decimal, actor=None, *, check_permission: bool = True) -> None:
    if check_permission and actor is not None and not actor.has_perm_code(roles.CLIENT_CREDIT_GRANT):
        raise ApiError("Vous n'avez pas l'autorisation d'accorder du crédit.", 403)
    if customer.is_credit_blocked:
        reason = f" ({customer.blocked_reason})" if customer.blocked_reason else ""
        raise ApiError(f"Le crédit de {customer.name} est bloqué{reason}.", 409)
    if customer.credit_limit_htg is not None and customer.balance_htg + amount > customer.credit_limit_htg + EPSILON:
        available = max(ZERO, customer.credit_limit_htg - customer.balance_htg)
        raise ApiError(f"Limite de crédit atteinte. Disponible : {available} HTG.", 409)


@transaction.atomic
def post_charge(customer: Customer, amount_htg, *, actor, description: str, paid_amount_htg=0, order=None,
                amount_usd=0, enforce_limit: bool = True, check_permission: bool = True) -> CustomerTransaction:
    amount = money(amount_htg)
    paid = money(paid_amount_htg)
    if amount <= 0 or paid < 0 or paid > amount:
        raise ApiError("Montant invalide.")
    customer = _lock(customer)
    credited = amount - paid
    if enforce_limit:
        ensure_credit_allowed(customer, credited, actor, check_permission=check_permission)
    customer.balance_htg = money(customer.balance_htg + credited)
    customer.save(update_fields=["balance_htg", "updated_at"])
    entry = CustomerTransaction.objects.create(
        business=customer.business,
        customer=customer,
        kind=CustomerTransaction.CHARGE,
        amount_htg=amount,
        amount_usd=money(amount_usd),
        paid_amount_htg=paid,
        balance_after_htg=customer.balance_htg,
        order=order,
        description=description[:200],
        **_actor_fields(actor),
    )
    audit(customer.business, "customer.charge", actor=actor, target=customer, amount=str(credited))
    return entry


@transaction.atomic
def post_payment(customer: Customer, amount_htg, *, actor, method: str = "cash", description: str = "Paiement reçu",
                 order=None) -> CustomerTransaction:
    amount = money(amount_htg)
    if amount <= 0:
        raise ApiError("Le montant doit être supérieur à zéro.")
    customer = _lock(customer)
    if amount > customer.balance_htg + EPSILON:
        raise ApiError(f"Le paiement dépasse le solde dû ({customer.balance_htg} HTG).")
    customer.balance_htg = max(ZERO, money(customer.balance_htg - amount))
    customer.save(update_fields=["balance_htg", "updated_at"])
    entry = CustomerTransaction.objects.create(
        business=customer.business,
        customer=customer,
        kind=CustomerTransaction.PAYMENT,
        amount_htg=amount,
        balance_after_htg=customer.balance_htg,
        order=order,
        description=description[:200],
        payment_method=method[:20],
        receipt_number=next_number(customer.business, "PAY"),
        **_actor_fields(actor),
    )
    audit(customer.business, "customer.payment", actor=actor, target=customer, amount=str(amount), method=method)
    return entry


@transaction.atomic
def post_adjustment(customer: Customer, amount_htg, *, actor, description: str) -> CustomerTransaction:
    """Signed: positive adds to what the client owes, negative forgives."""
    amount = money(amount_htg)
    if amount == 0:
        raise ApiError("Le montant ne peut pas être zéro.")
    if not description.strip():
        raise ApiError("Indiquez la raison de l'ajustement.")
    customer = _lock(customer)
    customer.balance_htg = max(ZERO, money(customer.balance_htg + amount))
    customer.save(update_fields=["balance_htg", "updated_at"])
    entry = CustomerTransaction.objects.create(
        business=customer.business,
        customer=customer,
        kind=CustomerTransaction.ADJUSTMENT,
        amount_htg=amount,
        balance_after_htg=customer.balance_htg,
        description=description[:200],
        **_actor_fields(actor),
    )
    audit(customer.business, "customer.adjustment", actor=actor, target=customer, amount=str(amount))
    return entry


@transaction.atomic
def issue_store_credit(customer: Customer, amount_htg, *, actor, description: str, order=None,
                       paylink=None) -> StoreCreditEntry:
    amount = money(amount_htg)
    if amount <= 0:
        raise ApiError("Le montant doit être supérieur à zéro.")
    customer = _lock(customer)
    customer.store_credit_htg = money(customer.store_credit_htg + amount)
    customer.save(update_fields=["store_credit_htg", "updated_at"])
    entry = StoreCreditEntry.objects.create(
        business=customer.business,
        customer=customer,
        kind=StoreCreditEntry.ISSUED,
        amount_htg=amount,
        balance_after_htg=customer.store_credit_htg,
        description=description[:200],
        order=order,
        paylink=paylink,
        **_actor_fields(actor),
    )
    audit(customer.business, "store_credit.issued", actor=actor, target=customer, amount=str(amount))
    return entry


@transaction.atomic
def redeem_store_credit(customer: Customer, amount_htg, *, actor, description: str, order=None) -> StoreCreditEntry:
    """Store credit is spendable cash, so the client must be identifiable."""
    amount = money(amount_htg)
    if amount <= 0:
        raise ApiError("Le montant doit être supérieur à zéro.")
    customer = _lock(customer)
    if not customer.has_store_credit_identity:
        raise ApiError("Complétez le prénom, le nom et une pièce d'identité (ou la date de naissance) du client.")
    if amount > customer.store_credit_htg + EPSILON:
        raise ApiError(f"Avoir insuffisant. Disponible : {customer.store_credit_htg} HTG.", 409)
    customer.store_credit_htg = max(ZERO, money(customer.store_credit_htg - amount))
    customer.save(update_fields=["store_credit_htg", "updated_at"])
    entry = StoreCreditEntry.objects.create(
        business=customer.business,
        customer=customer,
        kind=StoreCreditEntry.REDEEMED,
        amount_htg=amount,
        balance_after_htg=customer.store_credit_htg,
        description=description[:200],
        order=order,
        **_actor_fields(actor),
    )
    audit(customer.business, "store_credit.redeemed", actor=actor, target=customer, amount=str(amount))
    return entry

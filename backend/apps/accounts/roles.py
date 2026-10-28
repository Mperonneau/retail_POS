"""Retail roles and permissions, mirroring lib/core/permissions in the POS."""

from __future__ import annotations

OWNER = "owner"
ADMIN = "admin"
CASHIER = "cashier"
SELLER = "seller"

ROLE_CHOICES = [
    (OWNER, "Propriétaire"),
    (ADMIN, "Administrateur"),
    (CASHIER, "Caissier"),
    (SELLER, "Vendeur"),
]

SETTINGS_ACCESS = "settings_access"
REPORTS_VIEW = "reports_view"
CATALOG_MANAGE = "catalog_manage"
TRANSACTIONS_OPERATE = "transactions_operate"
FINANCIAL_CASH = "financial_cash"
CLIENT_CREDIT_GRANT = "client_credit_grant"

PERMISSIONS = (
    SETTINGS_ACCESS,
    REPORTS_VIEW,
    CATALOG_MANAGE,
    TRANSACTIONS_OPERATE,
    FINANCIAL_CASH,
    CLIENT_CREDIT_GRANT,
)

ROLE_DEFAULTS: dict[str, dict[str, bool]] = {
    OWNER: {p: True for p in PERMISSIONS},
    ADMIN: {p: True for p in PERMISSIONS},
    CASHIER: {
        SETTINGS_ACCESS: False,
        REPORTS_VIEW: False,
        CATALOG_MANAGE: True,
        TRANSACTIONS_OPERATE: True,
        FINANCIAL_CASH: True,
        CLIENT_CREDIT_GRANT: False,
    },
    SELLER: {
        SETTINGS_ACCESS: False,
        REPORTS_VIEW: False,
        CATALOG_MANAGE: False,
        TRANSACTIONS_OPERATE: True,
        FINANCIAL_CASH: False,
        CLIENT_CREDIT_GRANT: False,
    },
}

# Minutes of inactivity before the register locks back to the PIN pad.
IDLE_LOCK_MINUTES = {OWNER: 30, ADMIN: 30, CASHIER: 15, SELLER: 10}


def clean_permission_map(raw: object) -> dict[str, bool]:
    if not isinstance(raw, dict):
        return {}
    return {key: bool(value) for key, value in raw.items() if key in PERMISSIONS}


def effective_permissions(role: str, business_overrides: dict | None, staff_overrides: dict | None) -> dict[str, bool]:
    if role == OWNER:
        return {p: True for p in PERMISSIONS}
    result = dict(ROLE_DEFAULTS.get(role, ROLE_DEFAULTS[SELLER]))
    result.update(clean_permission_map((business_overrides or {}).get(role)))
    result.update(clean_permission_map(staff_overrides))
    return result

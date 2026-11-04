from __future__ import annotations


class SystemActor:
    """Acts for a business without a staff member (vitrine, webhooks, sync jobs)."""

    is_authenticated = False

    def __init__(self, business, name: str):
        self.business = business
        self.business_id = business.pk
        self.full_name = name
        self.role = "system"

    def has_perm_code(self, code: str) -> bool:
        return True

    def __str__(self) -> str:
        return self.full_name

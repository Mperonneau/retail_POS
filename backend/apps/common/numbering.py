from __future__ import annotations

from django.db import IntegrityError, transaction
from django.db.models import F
from django.utils import timezone

from .models import DocumentSequence


def next_number(business, prefix: str) -> str:
    """ORD-2026-0001 style numbers, gap-free per business, prefix and year."""
    year = timezone.localdate().year
    with transaction.atomic():
        updated = DocumentSequence.objects.filter(business=business, prefix=prefix, year=year).update(
            value=F("value") + 1
        )
        if not updated:
            try:
                with transaction.atomic():
                    DocumentSequence.objects.create(business=business, prefix=prefix, year=year, value=1)
            except IntegrityError:
                DocumentSequence.objects.filter(business=business, prefix=prefix, year=year).update(
                    value=F("value") + 1
                )
        value = DocumentSequence.objects.get(business=business, prefix=prefix, year=year).value
    return f"{prefix}-{year}-{value:04d}"

from __future__ import annotations

import uuid

from django.db import models


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)

    class Meta:
        abstract = True


class UUIDModel(TimeStampedModel):
    """Client-generated UUIDs are accepted so offline registers can create rows."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    class Meta:
        abstract = True


class TenantModel(UUIDModel):
    business = models.ForeignKey("accounts.Business", on_delete=models.CASCADE, related_name="+")

    class Meta:
        abstract = True


class DocumentSequence(models.Model):
    """Per-business, per-year counters for human numbers (ORD-2026-0001)."""

    business = models.ForeignKey("accounts.Business", on_delete=models.CASCADE, related_name="+")
    prefix = models.CharField(max_length=8)
    year = models.PositiveIntegerField()
    value = models.PositiveIntegerField(default=0)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["business", "prefix", "year"], name="uniq_doc_sequence"),
        ]


class AuditEvent(models.Model):
    """Append-only trail for money, stock, permission and device actions."""

    id = models.BigAutoField(primary_key=True)
    business = models.ForeignKey("accounts.Business", on_delete=models.CASCADE, related_name="+")
    actor = models.ForeignKey(
        "accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    actor_label = models.CharField(max_length=120, blank=True)
    device = models.ForeignKey("accounts.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    action = models.CharField(max_length=60)
    target_type = models.CharField(max_length=40, blank=True)
    target_id = models.CharField(max_length=64, blank=True)
    data = models.JSONField(default=dict, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        indexes = [models.Index(fields=["business", "-created_at"], name="audit_biz_recent")]
        ordering = ["-created_at"]


class IdempotencyRecord(models.Model):
    """Replays the first response when a register retries the same write."""

    business = models.ForeignKey("accounts.Business", on_delete=models.CASCADE, related_name="+")
    key = models.CharField(max_length=100)
    endpoint = models.CharField(max_length=200)
    status_code = models.PositiveSmallIntegerField()
    body = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["business", "key"], name="uniq_idempotency_key")]

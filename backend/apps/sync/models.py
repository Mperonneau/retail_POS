from django.db import models

from apps.common.models import TenantModel


class SyncOperation(TenantModel):
    """One queued register action. op_id makes a resent batch a no-op."""

    APPLIED = "applied"
    FAILED = "failed"

    op_id = models.CharField(max_length=64)
    kind = models.CharField(max_length=30)
    device = models.ForeignKey("accounts.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    staff = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    status = models.CharField(max_length=8, choices=[(APPLIED, "Appliquée"), (FAILED, "Refusée")])
    result = models.JSONField(default=dict, blank=True)
    error = models.CharField(max_length=300, blank=True)
    client_created_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["business", "op_id"], name="uniq_sync_op")]


class Tombstone(TenantModel):
    """Lets registers drop rows deleted elsewhere since their last pull."""

    entity = models.CharField(max_length=30)
    object_id = models.CharField(max_length=64)

    class Meta:
        indexes = [models.Index(fields=["business", "created_at"], name="tombstone_biz_since")]

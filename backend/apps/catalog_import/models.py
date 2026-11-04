from django.db import models

from apps.common.models import TimeStampedModel


class ImportJob(TimeStampedModel):
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    STATUSES = [(RUNNING, "En cours"), (SUCCEEDED, "Terminé"), (FAILED, "Échec")]

    id = models.CharField(primary_key=True, max_length=32)
    # Empty for jobs started through the legacy, unauthenticated route.
    business = models.ForeignKey("accounts.Business", null=True, blank=True, on_delete=models.CASCADE, related_name="+")
    created_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")
    status = models.CharField(max_length=10, choices=STATUSES, default=RUNNING)
    progress = models.CharField(max_length=120, blank=True)
    error = models.CharField(max_length=300, blank=True)
    file_names = models.JSONField(default=list, blank=True)
    draft = models.JSONField(default=dict, blank=True)
    report = models.JSONField(default=list, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    applied_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

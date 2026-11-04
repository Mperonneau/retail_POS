from django.db import models
from django.db.models import Q

from apps.common.models import TenantModel


class TimeclockEntry(TenantModel):
    staff = models.ForeignKey("accounts.StaffMember", on_delete=models.CASCADE, related_name="time_entries")
    staff_name = models.CharField(max_length=120)
    role = models.CharField(max_length=10)
    location = models.ForeignKey("accounts.Location", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    clock_in = models.DateTimeField()
    clock_out = models.DateTimeField(null=True, blank=True)
    # Set on the first manual edit so the original punch stays visible.
    original_clock_in = models.DateTimeField(null=True, blank=True)
    original_clock_out = models.DateTimeField(null=True, blank=True)
    is_manual = models.BooleanField(default=False)
    manual_entered_by = models.ForeignKey("accounts.StaffMember", null=True, blank=True, on_delete=models.SET_NULL,
                                          related_name="+")
    manual_entered_by_name = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-clock_in"]
        indexes = [models.Index(fields=["business", "clock_in"], name="timeclock_biz_in")]
        constraints = [
            models.UniqueConstraint(fields=["staff"], condition=Q(clock_out__isnull=True), name="one_open_shift_per_staff"),
        ]

    @property
    def duration_minutes(self) -> int | None:
        if self.clock_out is None:
            return None
        return int((self.clock_out - self.clock_in).total_seconds() // 60)

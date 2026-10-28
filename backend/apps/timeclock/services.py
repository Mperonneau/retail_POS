from __future__ import annotations

from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.common.audit import audit
from apps.common.exceptions import ApiError

from .models import TimeclockEntry


def open_entry(staff) -> TimeclockEntry | None:
    return TimeclockEntry.objects.filter(staff=staff, clock_out__isnull=True).first()


def _overlaps(staff, start, end, exclude_id=None) -> bool:
    qs = TimeclockEntry.objects.filter(staff=staff, clock_in__lt=end)
    if exclude_id:
        qs = qs.exclude(pk=exclude_id)
    now = timezone.now()
    return any((e.clock_out or now) > start for e in qs)


def clock_in(staff, *, location=None) -> TimeclockEntry:
    existing = open_entry(staff)
    if existing is not None:
        return existing
    try:
        with transaction.atomic():
            entry = TimeclockEntry.objects.create(business=staff.business, staff=staff, staff_name=staff.full_name,
                                                  role=staff.role, location=location, clock_in=timezone.now())
    except IntegrityError:
        return open_entry(staff)
    return entry


def clock_out(staff) -> TimeclockEntry:
    entry = open_entry(staff)
    if entry is None:
        raise ApiError("Aucun pointage en cours.", 409)
    entry.clock_out = timezone.now()
    entry.save(update_fields=["clock_out", "updated_at"])
    return entry


@transaction.atomic
def edit_entry(actor, entry: TimeclockEntry, *, clock_in=None, clock_out=None) -> TimeclockEntry:
    entry = TimeclockEntry.objects.select_for_update().get(pk=entry.pk)
    proposed_in = clock_in or entry.clock_in
    proposed_out = clock_out or entry.clock_out
    if proposed_out is not None and proposed_in >= proposed_out:
        raise ApiError("Le départ doit être après l'arrivée.")
    if _overlaps(entry.staff, proposed_in, proposed_out or timezone.now(), exclude_id=entry.pk):
        raise ApiError("Cette plage chevauche un autre quart de cet employé.", 409)
    if clock_in is None and clock_out is None:
        return entry
    if clock_in is not None:
        entry.original_clock_in = entry.original_clock_in or entry.clock_in
        entry.clock_in = clock_in
    if clock_out is not None:
        entry.original_clock_out = entry.original_clock_out or entry.clock_out
        entry.clock_out = clock_out
    entry.is_manual = True
    entry.manual_entered_by = actor
    entry.manual_entered_by_name = actor.full_name
    entry.save()
    audit(entry.business, "timeclock.edited", actor=actor, target=entry)
    return entry


def add_manual(actor, staff, *, clock_in, clock_out) -> TimeclockEntry:
    if clock_in is None or clock_out is None or clock_in >= clock_out:
        raise ApiError("Le départ doit être après l'arrivée.")
    if clock_out > timezone.now():
        raise ApiError("Le départ ne peut pas être dans le futur.")
    if _overlaps(staff, clock_in, clock_out):
        raise ApiError("Cette plage chevauche un autre quart de cet employé.", 409)
    entry = TimeclockEntry.objects.create(
        business=staff.business, staff=staff, staff_name=staff.full_name, role=staff.role, clock_in=clock_in,
        clock_out=clock_out, is_manual=True, manual_entered_by=actor, manual_entered_by_name=actor.full_name,
    )
    audit(staff.business, "timeclock.manual", actor=actor, target=entry)
    return entry

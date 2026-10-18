import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/staff_role.dart';
import '../models/timeclock_entry.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class TimeclockNotifier extends StateNotifier<List<TimeclockEntry>> {
  TimeclockNotifier() : super(_buildSeed());

  /// Two closed intervals [aStart, aEnd] and [bStart, bEnd] overlap in time.
  static bool shiftIntervalsOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  static DateTime _intervalEnd(TimeclockEntry e) =>
      e.clockOut ?? DateTime.now();

  /// Whether [newStart]/[newEnd] overlaps any of [employeeId]'s shifts except [excludeEntryId].
  bool overlapsExistingShift({
    required String employeeId,
    required DateTime newStart,
    required DateTime newEnd,
    String? excludeEntryId,
  }) {
    if (!newStart.isBefore(newEnd)) return false;
    for (final e in state) {
      if (e.employeeId != employeeId) continue;
      if (excludeEntryId != null && e.id == excludeEntryId) continue;
      final es = e.clockIn;
      final ee = _intervalEnd(e);
      if (shiftIntervalsOverlap(newStart, newEnd, es, ee)) return true;
    }
    return false;
  }

  // ── Public queries ──────────────────────────────────────────────────────────

  /// The currently open (not clocked-out) entry for [employeeId], or null.
  TimeclockEntry? openEntryFor(String employeeId) {
    for (final e in state) {
      if (e.employeeId == employeeId && e.isOpen) return e;
    }
    return null;
  }

  /// All entries for [employeeId] whose clock-in falls within [start]..[end].
  List<TimeclockEntry> entriesFor(
    String employeeId, {
    required DateTime start,
    required DateTime end,
  }) {
    return state.where((e) {
      if (e.employeeId != employeeId) return false;
      return !e.clockIn.isBefore(start) && !e.clockIn.isAfter(end);
    }).toList()
      ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
  }

  /// All entries whose clock-in falls within [start]..[end].
  List<TimeclockEntry> entriesForPeriod({
    required DateTime start,
    required DateTime end,
  }) {
    return state.where((e) {
      return !e.clockIn.isBefore(start) && !e.clockIn.isAfter(end);
    }).toList()
      ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  /// Clock [employeeId] in right now.  No-op if already open.
  TimeclockEntry clockIn({
    required String employeeId,
    required String employeeName,
    required StaffRole role,
  }) {
    final existing = openEntryFor(employeeId);
    if (existing != null) return existing;

    final entry = TimeclockEntry(
      id: '${employeeId}_${DateTime.now().millisecondsSinceEpoch}',
      employeeId: employeeId,
      employeeName: employeeName,
      role: role,
      clockIn: DateTime.now(),
    );
    state = [...state, entry];
    return entry;
  }

  /// Clock [employeeId] out right now.  Returns the closed entry, or null.
  TimeclockEntry? clockOut(String employeeId) {
    final open = openEntryFor(employeeId);
    if (open == null) return null;
    final closed = open.copyWith(clockOut: DateTime.now());
    state = [
      for (final e in state)
        if (e.id == open.id) closed else e,
    ];
    return closed;
  }

  /// Admin override: change clock-in / clock-out. Marks manual + editor.
  /// Returns `null` on success, or an error message.
  String? editEntry(
    String id, {
    DateTime? newClockIn,
    DateTime? newClockOut,
    required String enteredByName,
    String? enteredById,
  }) {
    final e = state.where((x) => x.id == id).firstOrNull;
    if (e == null) return 'Entrée introuvable.';

    final proposedIn = newClockIn ?? e.clockIn;
    final proposedOut = newClockOut ?? e.clockOut;

    if (proposedOut != null && !proposedIn.isBefore(proposedOut)) {
      return 'Le départ doit être après l\'arrivée.';
    }

    if (overlapsExistingShift(
      employeeId: e.employeeId,
      newStart: proposedIn,
      newEnd: proposedOut ?? DateTime.now(),
      excludeEntryId: id,
    )) {
      return 'Cette plage chevauche un autre quart de cet employé.';
    }

    final changed = newClockIn != null || newClockOut != null;
    if (!changed) return null;

    state = [
      for (final x in state)
        if (x.id == id)
          x.copyWith(
            clockIn: newClockIn ?? x.clockIn,
            clockOut: newClockOut ?? x.clockOut,
            originalClockIn: newClockIn != null
                ? (x.originalClockIn ?? x.clockIn)
                : x.originalClockIn,
            originalClockOut: newClockOut != null
                ? (x.originalClockOut ?? x.clockOut)
                : x.originalClockOut,
            isManual: true,
            manualEnteredByName: enteredByName,
            manualEnteredById: enteredById,
          )
        else
          x,
    ];
    return null;
  }

  /// Admin: add a closed shift (forgot to clock). Returns `null` on success.
  String? addManualShift({
    required String employeeId,
    required String employeeName,
    required StaffRole role,
    required DateTime clockIn,
    required DateTime clockOut,
    required String enteredByName,
    String? enteredById,
  }) {
    if (!clockIn.isBefore(clockOut)) {
      return 'Le départ doit être après l\'arrivée.';
    }
    if (overlapsExistingShift(
      employeeId: employeeId,
      newStart: clockIn,
      newEnd: clockOut,
    )) {
      return 'Cette plage chevauche un quart déjà enregistré ce jour-là.';
    }

    final entry = TimeclockEntry(
      id: '${employeeId}_manual_${DateTime.now().millisecondsSinceEpoch}',
      employeeId: employeeId,
      employeeName: employeeName,
      role: role,
      clockIn: clockIn,
      clockOut: clockOut,
      isManual: true,
      manualEnteredByName: enteredByName,
      manualEnteredById: enteredById,
    );
    state = [...state, entry];
    return null;
  }

  // ── Mock seed ───────────────────────────────────────────────────────────────

  static List<TimeclockEntry> _buildSeed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <TimeclockEntry>[];

    // Employees to seed (mirrors StaffDirectoryProvider seed)
    const staff = [
      ('seed_1', 'Jean-Marc Dupont', StaffRole.admin),
      ('seed_2', 'Marie-Carmel Joseph', StaffRole.seller),
      ('seed_3', 'Pierre Laguerre', StaffRole.seller),
      ('seed_4', 'Roseline Janvier', StaffRole.cashier),
      ('seed_6', 'Claudine Bernard', StaffRole.seller),
      ('seed_7', 'Sophie Laurent', StaffRole.seller),
    ];

    // Generate 14 days of past data (skip Sundays)
    for (var dayOffset = 13; dayOffset >= 0; dayOffset--) {
      final day = today.subtract(Duration(days: dayOffset));
      if (day.weekday == DateTime.sunday) continue; // closed Sundays

      for (final (id, name, role) in staff) {
        // Randomly skip ~15% of shifts (unavailable days)
        final hash = (id.hashCode ^ day.day ^ day.month) & 0xFF;
        if (hash > 217) continue; // ~15% skip

        final inHour  = 7 + (hash % 2);          // 7 or 8 AM
        final inMin   = (hash * 7) % 60;
        final shiftH  = 7 + (hash % 3);           // 7–9 hour shift
        final outMin  = (hash * 13) % 60;

        final clockIn = DateTime(day.year, day.month, day.day, inHour, inMin);
        DateTime? clockOut;

        // Today's first shift: leave open (employee is still working)
        final isToday = dayOffset == 0;
        final isFirstForToday = isToday && entries.where((e) => e.employeeId == id && _sameDay(e.clockIn, today)).isEmpty;
        if (isFirstForToday) {
          clockOut = null;
        } else {
          final outHour = inHour + shiftH;
          clockOut = DateTime(day.year, day.month, day.day, outHour, outMin);
        }

        entries.add(TimeclockEntry(
          id: '${id}_seed_$dayOffset',
          employeeId: id,
          employeeName: name,
          role: role,
          clockIn: clockIn,
          clockOut: clockOut,
        ));
      }
    }
    return entries;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

final timeclockProvider =
    StateNotifierProvider<TimeclockNotifier, List<TimeclockEntry>>(
  (ref) => TimeclockNotifier(),
);

// ─── Period helpers ───────────────────────────────────────────────────────────

enum TimeclockPeriod { week, biweek, month }

String timeclockPeriodLabel(TimeclockPeriod p) => switch (p) {
      TimeclockPeriod.week => 'Cette semaine',
      TimeclockPeriod.biweek => 'Last 2 Weeks',
      TimeclockPeriod.month => 'Ce mois',
    };

/// Returns [start, end] for the given period relative to now.
(DateTime start, DateTime end) periodRange(TimeclockPeriod period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 23, 59, 59);

  switch (period) {
    case TimeclockPeriod.week:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return (DateTime(monday.year, monday.month, monday.day), today);
    case TimeclockPeriod.biweek:
      return (today.subtract(const Duration(days: 13)), today);
    case TimeclockPeriod.month:
      return (DateTime(now.year, now.month, 1), today);
  }
}

/// Total duration summed from a list of entries (open entries use now).
Duration totalDuration(List<TimeclockEntry> entries) {
  Duration total = Duration.zero;
  for (final e in entries) {
    total += e.duration;
  }
  return total;
}

/// Format a [Duration] as "Xh Ym", e.g. "32h 15m".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

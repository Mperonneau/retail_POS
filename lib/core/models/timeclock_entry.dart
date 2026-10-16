import 'staff_role.dart';

/// One clock-in / clock-out record for a single employee shift.
class TimeclockEntry {
  final String id;
  final String employeeId;
  final String employeeName;
  final StaffRole role;

  /// Current (possibly admin-edited) clock-in time.
  final DateTime clockIn;

  /// Current (possibly admin-edited) clock-out time. `null` = shift still open.
  final DateTime? clockOut;

  /// Original clock-in time before any admin edit.  `null` = never edited.
  final DateTime? originalClockIn;

  /// Original clock-out time before any admin edit.  `null` = never edited.
  final DateTime? originalClockOut;

  /// True if this row was created or last changed via admin manual entry/edit.
  final bool isManual;

  /// Display name of the staff member who manually added or last edited this row.
  final String? manualEnteredByName;

  /// Optional id of that staff member (for future API sync).
  final String? manualEnteredById;

  const TimeclockEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.clockIn,
    this.clockOut,
    this.originalClockIn,
    this.originalClockOut,
    this.isManual = false,
    this.manualEnteredByName,
    this.manualEnteredById,
  });

  bool get isOpen => clockOut == null;

  bool get clockInEdited => originalClockIn != null;
  bool get clockOutEdited => originalClockOut != null;

  Duration get duration {
    final end = clockOut ?? DateTime.now();
    return end.difference(clockIn);
  }

  String get durationLabel {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static const _absent = Object();

  TimeclockEntry copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    StaffRole? role,
    DateTime? clockIn,
    Object? clockOut = _absent,
    Object? originalClockIn = _absent,
    Object? originalClockOut = _absent,
    bool? isManual,
    Object? manualEnteredByName = _absent,
    Object? manualEnteredById = _absent,
  }) =>
      TimeclockEntry(
        id: id ?? this.id,
        employeeId: employeeId ?? this.employeeId,
        employeeName: employeeName ?? this.employeeName,
        role: role ?? this.role,
        clockIn: clockIn ?? this.clockIn,
        clockOut: clockOut == _absent ? this.clockOut : clockOut as DateTime?,
        originalClockIn: originalClockIn == _absent
            ? this.originalClockIn
            : originalClockIn as DateTime?,
        originalClockOut: originalClockOut == _absent
            ? this.originalClockOut
            : originalClockOut as DateTime?,
        isManual: isManual ?? this.isManual,
        manualEnteredByName: manualEnteredByName == _absent
            ? this.manualEnteredByName
            : manualEnteredByName as String?,
        manualEnteredById: manualEnteredById == _absent
            ? this.manualEnteredById
            : manualEnteredById as String?,
      );
}

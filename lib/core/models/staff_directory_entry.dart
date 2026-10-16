import 'staff_role.dart';

/// One employee row for Settings + PIN login (mock).
/// In production the backend stores a bcrypt hash of the PIN, not [pinDigits].
class StaffDirectoryEntry {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final StaffRole role;
  /// Demo / dev only — replace with server-side verification.
  final String pinDigits;
  final bool isActive;

  const StaffDirectoryEntry({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.pinDigits,
    this.isActive = true,
  });

  StaffDirectoryEntry copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    StaffRole? role,
    String? pinDigits,
    bool? isActive,
  }) =>
      StaffDirectoryEntry(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        pinDigits: pinDigits ?? this.pinDigits,
        isActive: isActive ?? this.isActive,
      );
}

import '../models/staff_directory_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_settings_provider.dart';
import '../providers/staff_session_provider.dart';
import 'permission_id.dart';

/// Someone allowed to put a balance on a client account.
class CreditGrantStaff {
  final String employeeId;
  final String name;
  final StaffRole role;

  const CreditGrantStaff({
    required this.employeeId,
    required this.name,
    required this.role,
  });
}

bool employeeCanGrantClientCredit({
  required String employeeId,
  required StaffRole role,
  required ActiveModule module,
  required PermissionSettingsState settings,
}) {
  if (settings.ownerPowerIds.contains(employeeId)) return true;
  final base =
      settings.roleDefaults[module]?[role]?[PermissionId.clientCreditGrant] ??
      false;
  final override =
      settings.userOverrides[employeeId]?[PermissionId.clientCreditGrant];
  return override ?? base;
}

/// A shop account with no staff PIN may grant credit. A staff session
/// must hold [PermissionId.clientCreditGrant].
bool currentUserCanGrantClientCredit({
  required StaffSessionState? session,
  required bool shopAccountSignedIn,
  required ActiveModule module,
  required PermissionSettingsState settings,
}) {
  if (session == null) return shopAccountSignedIn;
  return employeeCanGrantClientCredit(
    employeeId: session.employeeId,
    role: session.role,
    module: module,
    settings: settings,
  );
}

/// Active directory row for this PIN, otherwise a demo PIN.
CreditGrantStaff? lookupStaffByPin(
  String pin,
  List<StaffDirectoryEntry> directory,
) {
  final digits = pin.trim();
  if (digits.length != 4) return null;
  for (final entry in directory) {
    if (entry.isActive && entry.pinDigits == digits) {
      return CreditGrantStaff(
        employeeId: entry.id,
        name: entry.fullName,
        role: entry.role,
      );
    }
  }
  final role = switch (digits) {
    '1234' => StaffRole.cashier,
    '1111' => StaffRole.seller,
    '2222' => StaffRole.owner,
    '3333' => StaffRole.admin,
    '4444' => StaffRole.kitchen,
    '8888' => StaffRole.reception,
    _ => null,
  };
  if (role == null) return null;
  return CreditGrantStaff(
    employeeId: 'emp_${digits}_demo',
    name: switch (role) {
      StaffRole.owner => 'Propriétaire',
      StaffRole.admin => 'Admin',
      StaffRole.manager => 'Gérant',
      StaffRole.cashier => 'Jean (Cashier)',
      StaffRole.seller => 'Vendeur',
      StaffRole.waiter => 'Marie (Waiter)',
      StaffRole.reception => 'Sophie (Reception)',
      StaffRole.kitchen => 'Cuisine',
    },
    role: role,
  );
}

/// Employee role for PIN session + directory (maps to backend `Employee.role`).
enum StaffRole {
  waiter,
  cashier,
  /// Hotel front desk: rooms, reservations; often also restaurant cash / hotel cash.
  reception,
  manager,
  admin,
  kitchen,
}

/// Idle timeout before returning to PIN. Never exceeds [maxIdleDuration].
const Duration maxIdleDuration = Duration(minutes: 30);

Duration effectiveIdleDuration(StaffRole role) {
  final base = switch (role) {
    StaffRole.cashier => const Duration(minutes: 30),
    StaffRole.reception => const Duration(minutes: 30),
    StaffRole.waiter => const Duration(minutes: 5),
    StaffRole.manager => const Duration(minutes: 20),
    StaffRole.admin => const Duration(minutes: 15),
    StaffRole.kitchen => const Duration(minutes: 10),
  };
  return base > maxIdleDuration ? maxIdleDuration : base;
}

String staffRoleDisplayLabel(StaffRole role) {
  switch (role) {
    case StaffRole.admin:
      return 'Admin';
    case StaffRole.manager:
      return 'Manager';
    case StaffRole.waiter:
      return 'Waiter';
    case StaffRole.cashier:
      return 'Cashier';
    case StaffRole.reception:
      return 'Reception';
    case StaffRole.kitchen:
      return 'Kitchen';
  }
}

/// Kitchen display / KDS: session does not auto-log out on idle (screen is often
/// watched, not touched). [effectiveIdleDuration] for [StaffRole.kitchen] is
/// ignored by [StaffSessionNotifier].
bool isRoleExemptFromIdleLogout(StaffRole role) => role == StaffRole.kitchen;

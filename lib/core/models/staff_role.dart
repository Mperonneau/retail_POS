import '../providers/auth_provider.dart';

/// Employee role for PIN session + directory (maps to backend `Employee.role`).
enum StaffRole {
  waiter,
  cashier,
  /// Hotel front desk: rooms, reservations; often also restaurant cash / hotel cash.
  reception,
  manager,
  admin,
  kitchen,
  /// Retail shop owner. Same default rights as [admin].
  owner,
  /// Retail floor seller. An owner or admin can grant this person owner rights.
  seller,
}

/// Roles shown for the active module. Retail is a shop, not a restaurant.
List<StaffRole> staffRolesForModule(ActiveModule module) {
  if (module == ActiveModule.retail) {
    return const [
      StaffRole.owner,
      StaffRole.admin,
      StaffRole.cashier,
      StaffRole.seller,
    ];
  }
  return const [
    StaffRole.waiter,
    StaffRole.cashier,
    StaffRole.reception,
    StaffRole.manager,
    StaffRole.admin,
    StaffRole.kitchen,
  ];
}

/// Owner and admin (and the legacy manager, who has the same rights) may
/// give a seller the owner's rights.
bool roleCanGrantOwnerPower(StaffRole role) =>
    role == StaffRole.owner ||
    role == StaffRole.admin ||
    role == StaffRole.manager;

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
    StaffRole.owner => const Duration(minutes: 20),
    StaffRole.seller => const Duration(minutes: 30),
  };
  return base > maxIdleDuration ? maxIdleDuration : base;
}

String staffRoleDisplayLabel(StaffRole role) {
  switch (role) {
    case StaffRole.owner:
      return 'Propriétaire';
    case StaffRole.admin:
      return 'Admin';
    case StaffRole.manager:
      return 'Gérant';
    case StaffRole.seller:
      return 'Vendeur';
    case StaffRole.waiter:
      return 'Serveur';
    case StaffRole.cashier:
      return 'Caissier';
    case StaffRole.reception:
      return 'Réception';
    case StaffRole.kitchen:
      return 'Cuisine';
  }
}

/// Kitchen display / KDS: session does not auto-log out on idle (screen is often
/// watched, not touched). [effectiveIdleDuration] for [StaffRole.kitchen] is
/// ignored by [StaffSessionNotifier].
bool isRoleExemptFromIdleLogout(StaffRole role) => role == StaffRole.kitchen;

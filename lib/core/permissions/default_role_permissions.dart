import '../models/staff_role.dart';
import '../providers/auth_provider.dart';
import 'permission_id.dart';

/// Baseline toggles per role × module (mock until API).
Map<PermissionId, bool> defaultPermissionsForRole(
  ActiveModule module,
  StaffRole role,
) {
  switch (role) {
    case StaffRole.admin:
    case StaffRole.manager:
      return {for (final p in PermissionId.values) p: true};
    case StaffRole.cashier:
      return _cashierDefaults(module);
    case StaffRole.reception:
      return _receptionDefaults(module);
    case StaffRole.waiter:
      return _waiterDefaults(module);
    case StaffRole.kitchen:
      return _kitchenDefaults(module);
  }
}

/// Front desk + cash (restaurant / hotel) without catalog/settings — mirrors Haiti front desk reality.
Map<PermissionId, bool> _receptionDefaults(ActiveModule module) {
  switch (module) {
    case ActiveModule.hotel:
    case ActiveModule.restaurant:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: false,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: true,
      };
    case ActiveModule.retail:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: true,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: true,
      };
  }
}

Map<PermissionId, bool> _cashierDefaults(ActiveModule module) {
  switch (module) {
    case ActiveModule.retail:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: true,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: true,
      };
    case ActiveModule.restaurant:
    case ActiveModule.hotel:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: false,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: true,
      };
  }
}

Map<PermissionId, bool> _waiterDefaults(ActiveModule module) {
  switch (module) {
    case ActiveModule.restaurant:
    case ActiveModule.hotel:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: false,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: false,
      };
    case ActiveModule.retail:
      return {
        PermissionId.settingsAccess: false,
        PermissionId.reportsView: false,
        PermissionId.catalogManage: false,
        PermissionId.transactionsOperate: true,
        PermissionId.financialCash: false,
      };
  }
}

Map<PermissionId, bool> _kitchenDefaults(ActiveModule module) {
  // KDS: only kitchen + minimal navigation; no settings/reports/catalog/cash.
  return {
    PermissionId.settingsAccess: false,
    PermissionId.reportsView: false,
    PermissionId.catalogManage: false,
    PermissionId.transactionsOperate: true,
    PermissionId.financialCash: false,
  };
}

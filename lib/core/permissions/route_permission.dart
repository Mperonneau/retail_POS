import '../navigation/app_routes.dart';
import '../providers/auth_provider.dart';
import '../models/staff_role.dart';
import 'permission_id.dart';

/// Primary permission required for a shell route. `null` = always allow if logged in.
PermissionId? permissionRequiredForRoute(String route, ActiveModule module) {
  if (route.endsWith('/settings') || route.endsWith('/vitrine')) {
    return PermissionId.settingsAccess;
  }
  if (route.contains('/reports')) return PermissionId.reportsView;
  if (route.contains('/timeclock')) return PermissionId.reportsView;

  if (route.contains('cash-control') ||
      route.contains('cash-reconciliation') ||
      route == AppRoutes.retailCashier) {
    return PermissionId.financialCash;
  }

  if (route.contains('/menu') ||
      route.contains('/inventory') ||
      route.contains('/products') ||
      route.contains('/suppliers') ||
      route.contains('purchase-orders')) {
    return PermissionId.catalogManage;
  }

  if (route.contains('/dashboard')) return null;

  // Default: operational routes (tables, orders, POS, rooms, guests, etc.)
  return PermissionId.transactionsOperate;
}

/// Kitchen role: only dashboard + kitchen route (module-specific).
bool isKitchenRestrictedNav(StaffRole role) => role == StaffRole.kitchen;

String? kitchenRouteForModule(ActiveModule module) {
  switch (module) {
    case ActiveModule.restaurant:
      return AppRoutes.restaurantKitchen;
    case ActiveModule.hotel:
      return AppRoutes.hotelRestaurantKitchen;
    case ActiveModule.retail:
      return null;
  }
}

bool routeAllowedForKitchenRole(String route, ActiveModule module) {
  final k = kitchenRouteForModule(module);
  if (k != null && route == k) return true;
  if (module == ActiveModule.restaurant &&
      route == AppRoutes.restaurantKitchenCompleted) {
    return true;
  }
  if (module == ActiveModule.hotel &&
      route == AppRoutes.hotelRestaurantKitchenCompleted) {
    return true;
  }
  // Allow dashboard as home anchor for kitchen on all modules.
  switch (module) {
    case ActiveModule.restaurant:
      return route == AppRoutes.restaurantDashboard;
    case ActiveModule.hotel:
      return route == AppRoutes.hotelDashboard;
    case ActiveModule.retail:
      return route == AppRoutes.retailDashboard || route == AppRoutes.retailPos;
  }
}

bool canAccessShellRoute({
  required String route,
  required ActiveModule module,
  required Map<PermissionId, bool> perms,
  required StaffRole role,
}) {
  if (isKitchenRestrictedNav(role)) {
    return routeAllowedForKitchenRole(route, module);
  }

  final req = permissionRequiredForRoute(route, module);
  if (req == null) return true;
  return perms[req] == true;
}

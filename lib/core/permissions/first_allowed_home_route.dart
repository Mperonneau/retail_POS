import '../models/staff_role.dart';
import '../navigation/app_routes.dart';
import '../providers/auth_provider.dart';
import '../utils/navigation_helpers.dart';
import 'permission_id.dart';
import 'route_permission.dart';

/// Primary screen for front-line roles (when [canAccessShellRoute] allows it).
String? _preferredRoleHomeRoute(ActiveModule module, StaffRole role) {
  switch (module) {
    case ActiveModule.restaurant:
      if (role == StaffRole.waiter || role == StaffRole.cashier) {
        return AppRoutes.restaurantOrders;
      }
      return null;
    case ActiveModule.hotel:
      if (role == StaffRole.reception) {
        return AppRoutes.hotelRooms;
      }
      return null;
    case ActiveModule.retail:
      if (role == StaffRole.cashier) {
        return AppRoutes.retailPos;
      }
      return null;
  }
}

/// First shell route the user may open after PIN (or when redirecting away from a blocked route).
String firstAllowedHomeRoute({
  required ActiveModule module,
  required StaffRole role,
  required Map<PermissionId, bool> perms,
}) {
  if (isKitchenRestrictedNav(role)) {
    final k = kitchenRouteForModule(module);
    if (k != null &&
        canAccessShellRoute(
          route: k,
          module: module,
          perms: perms,
          role: role,
        )) {
      return k;
    }
    switch (module) {
      case ActiveModule.restaurant:
        return AppRoutes.restaurantDashboard;
      case ActiveModule.hotel:
        return AppRoutes.hotelDashboard;
      case ActiveModule.retail:
        if (canAccessShellRoute(
          route: AppRoutes.retailPos,
          module: module,
          perms: perms,
          role: role,
        )) {
          return AppRoutes.retailPos;
        }
        return AppRoutes.retailDashboard;
    }
  }

  final preferred = _preferredRoleHomeRoute(module, role);
  if (preferred != null &&
      canAccessShellRoute(
        route: preferred,
        module: module,
        perms: perms,
        role: role,
      )) {
    return preferred;
  }

  final candidates = switch (module) {
    ActiveModule.restaurant => [
      AppRoutes.restaurantDashboard,
      AppRoutes.restaurantTables,
      AppRoutes.restaurantOrders,
      AppRoutes.restaurantKitchen,
      AppRoutes.restaurantKitchenCompleted,
      AppRoutes.restaurantMenu,
      AppRoutes.restaurantInventory,
      AppRoutes.restaurantCashControl,
      AppRoutes.restaurantReports,
      AppRoutes.restaurantCustomers,
      AppRoutes.restaurantOrderHistory,
      AppRoutes.restaurantSettings,
    ],
    ActiveModule.hotel => [
      AppRoutes.hotelDashboard,
      AppRoutes.hotelRooms,
      AppRoutes.hotelReservations,
      AppRoutes.hotelCheckIn,
      AppRoutes.hotelRestaurantTables,
      AppRoutes.hotelRestaurantOrders,
      AppRoutes.hotelRestaurantKitchen,
      AppRoutes.hotelRestaurantKitchenCompleted,
      AppRoutes.hotelRestaurantMenu,
      AppRoutes.hotelFrontDeskCashControl,
      AppRoutes.hotelReports,
      AppRoutes.hotelOrderHistory,
      AppRoutes.hotelCustomers,
      AppRoutes.hotelSettings,
    ],
    ActiveModule.retail => [
      AppRoutes.retailDashboard,
      AppRoutes.retailPos,
      AppRoutes.retailProducts,
      AppRoutes.retailInventory,
      AppRoutes.retailSuppliers,
      AppRoutes.retailPurchaseOrders,
      AppRoutes.retailCustomers,
      AppRoutes.retailOrderHistory,
      AppRoutes.retailCollections,
      AppRoutes.retailCashier,
      AppRoutes.retailCashControl,
      AppRoutes.retailReports,
      AppRoutes.retailSettings,
    ],
  };

  for (final r in candidates) {
    if (canAccessShellRoute(
      route: r,
      module: module,
      perms: perms,
      role: role,
    )) {
      return r;
    }
  }
  return dashboardPathForModule(module);
}

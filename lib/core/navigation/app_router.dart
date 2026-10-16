import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_settings_provider.dart';
import '../providers/staff_session_provider.dart';
import '../navigation/app_shell.dart';
import '../navigation/app_routes.dart';
import '../permissions/first_allowed_home_route.dart';
import '../permissions/route_permission.dart';
import '../utils/navigation_helpers.dart';

import '../../auth/screens/splash_screen.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/forgot_password_screen.dart';
import '../../auth/screens/register_screen.dart';
import '../../auth/screens/pin_screen.dart';

import '../../core/screens/customers/customer_list_screen.dart';
import '../../core/screens/customers/collections_dashboard_screen.dart';

import '../../retail/screens/retail_dashboard.dart';
import '../../retail/screens/pos_screen.dart';
import '../../retail/screens/product_management.dart';
import '../../retail/screens/retail_inventory_screen.dart';
import '../../retail/screens/supplier_screen.dart';
import '../../retail/screens/purchase_orders_screen.dart';
import '../../retail/screens/sales_history.dart';
import '../../retail/screens/cashier_session.dart';
import '../../retail/screens/retail_cash_control_screen.dart';
import '../../retail/screens/retail_cash_reconciliation_screen.dart';
import '../../retail/screens/retail_reports.dart';
import '../../retail/screens/quotes_screen.dart';

import '../../settings/screens/settings_screen.dart';
import '../../payments/screens/payment_flow_screen.dart';
import '../screens/order_history/order_history_screen.dart';
import '../screens/timeclock/timeclock_screen.dart';
import '../screens/paylinks/paylink_screen.dart';
import '../models/paylink.dart';
import '../models/customer.dart' show customerProvider;

NoTransitionPage<void> _noTransitionPage(
  GoRouterState state,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

bool _isShellRoute(String loc) => loc.startsWith('/retail/');

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  // Only presence matters for redirects — watching full state rebuilds GoRouter on
  // every idle activity tick and freezes the UI.
  final hasStaff =
      ref.watch(staffSessionProvider.select((s) => s != null));
  ref.watch(permissionSettingsProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isAuth = authState.status == AuthStatus.authenticated;

      final isPublicUnauth = loc == AppRoutes.splash ||
          loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.forgotPassword;

      if (!isAuth) {
        if (loc == AppRoutes.pin) return AppRoutes.login;
        if (!isPublicUnauth) return AppRoutes.login;
        return null;
      }

      // Tier 1 OK — staff PIN required before module UI
      if (!hasStaff) {
        if (loc == AppRoutes.pin) return null;
        if (isPublicUnauth) {
          if (loc == AppRoutes.splash) return AppRoutes.pin;
          if (loc == AppRoutes.login || loc == AppRoutes.register) {
            return AppRoutes.pin;
          }
          if (loc == AppRoutes.forgotPassword) return AppRoutes.pin;
          return null;
        }
        return AppRoutes.pin;
      }

      if (loc == AppRoutes.pin ||
          loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.splash) {
        final staff = ref.read(staffSessionProvider);
        if (staff != null) {
          final perms = ref.read(effectivePermissionsProvider);
          return firstAllowedHomeRoute(
            module: authState.module,
            role: staff.role,
            perms: perms,
          );
        }
        return dashboardPathForModule(authState.module);
      }
      if (loc == AppRoutes.forgotPassword) {
        final staff = ref.read(staffSessionProvider);
        if (staff != null) {
          final perms = ref.read(effectivePermissionsProvider);
          return firstAllowedHomeRoute(
            module: authState.module,
            role: staff.role,
            perms: perms,
          );
        }
        return dashboardPathForModule(authState.module);
      }

      // Legacy /settings — resolve to the correct shell (duplicate child paths are ambiguous).
      if (state.uri.path == '/settings') {
        switch (authState.module) {
          case ActiveModule.restaurant:
            return AppRoutes.restaurantSettings;
          case ActiveModule.hotel:
            return AppRoutes.hotelSettings;
          case ActiveModule.retail:
            return AppRoutes.retailSettings;
        }
      }

      if (hasStaff && _isShellRoute(loc)) {
        final staff = ref.read(staffSessionProvider);
        if (staff != null) {
          final perms = ref.read(effectivePermissionsProvider);
          if (!canAccessShellRoute(
            route: loc,
            module: authState.module,
            perms: perms,
            role: staff.role,
          )) {
            return firstAllowedHomeRoute(
              module: authState.module,
              role: staff.role,
              perms: perms,
            );
          }
        }
      }
      return null;
    },
    routes: [
      // --- Auth Routes ---
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
          path: AppRoutes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(path: AppRoutes.pin, builder: (_, __) => const PinScreen()),

      // --- Retail Shell ---
      ShellRoute(
        builder: (context, state, child) => AppShell(
          module: ActiveModule.retail,
          child: child,
        ),
        routes: [
          GoRoute(
              path: AppRoutes.retailDashboard,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const RetailDashboard())),
          GoRoute(
              path: AppRoutes.retailPos,
              pageBuilder: (_, state) {
                final args = RetailPosRouteArgs.parse(state.extra);
                return _noTransitionPage(
                  state,
                  PosScreen(
                    isQuoteMode: args.quoteMode || args.quoteToEdit != null,
                    quoteToEdit: args.quoteToEdit,
                  ),
                );
              }),
          GoRoute(
              path: AppRoutes.retailProducts,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const ProductManagement())),
          GoRoute(
              path: AppRoutes.retailInventory,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const RetailInventoryScreen())),
          GoRoute(
              path: AppRoutes.retailSuppliers,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const SupplierScreen())),
          GoRoute(
              path: AppRoutes.retailPurchaseOrders,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const PurchaseOrdersScreen())),
          GoRoute(
              path: AppRoutes.retailCustomers,
              pageBuilder: (_, state) => _noTransitionPage(
                    state,
                    CustomerListScreen(
                      backRoute: AppRoutes.retailDashboard,
                      detailRoute: AppRoutes.retailCustomerDetail,
                      formRoute: AppRoutes.retailCustomerForm,
                      collectionsRoute: AppRoutes.retailCollections,
                    ),
                  )),
          GoRoute(
              path: AppRoutes.retailCollections,
              pageBuilder: (_, state) => _noTransitionPage(
                    state,
                    CollectionsDashboardScreen(
                      formRoute: AppRoutes.retailCustomerForm,
                    ),
                  )),
          GoRoute(
              path: AppRoutes.retailSalesHistory,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const SalesHistory())),
          GoRoute(
              path: AppRoutes.retailCashier,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const CashierSession())),
          GoRoute(
              path: AppRoutes.retailCashControl,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const RetailCashControlScreen())),
          GoRoute(
              path: AppRoutes.retailCashReconciliation,
              pageBuilder: (_, state) => _noTransitionPage(
                    state,
                    const RetailCashReconciliationScreen(),
                  )),
          GoRoute(
              path: AppRoutes.retailReports,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const RetailReports())),
          GoRoute(
              path: AppRoutes.retailOrderHistory,
              pageBuilder: (_, state) => _noTransitionPage(
                    state,
                    const OrderHistoryScreen(
                      scope: OrderHistoryListScope.retail,
                    ),
                  )),
          GoRoute(
              path: AppRoutes.retailPayLinks,
              pageBuilder: (_, state) => _noTransitionPage(
                    state,
                    PayLinkScreen(
                      payLinkProvider: retailPayLinkProvider,
                      customerProvider: customerProvider,
                    ),
                  )),
          GoRoute(
              path: AppRoutes.retailQuotes,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const QuotesScreen())),
          GoRoute(
              path: AppRoutes.retailTimeclock,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const TimeclockScreen())),
          GoRoute(
              path: AppRoutes.retailSettings,
              pageBuilder: (_, state) =>
                  _noTransitionPage(state, const SettingsScreen())),
        ],
      ),

      GoRoute(
          path: AppRoutes.paymentFlow,
          builder: (_, __) => const PaymentFlowScreen()),
    ],
  );
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../permissions/route_permission.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_settings_provider.dart';
import '../providers/staff_session_provider.dart';
import '../utils/staff_name_utils.dart';
import '../utils/staff_session_navigation.dart';
import '../providers/sidebar_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/date_formatter.dart';
import '../utils/navigation_helpers.dart';
import '../widgets/app_bottom_sheet.dart';
import '../providers/device_session_provider.dart';
import '../widgets/connectivity_dot.dart';
import '../widgets/offline_banner.dart';
import '../widgets/keyboard_scroll_shortcuts.dart';
import '../widgets/loading_overlay.dart';
import 'app_routes.dart';

class _NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;

  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });
}

// Groups are used for visual section headers in the sidebar (hotel module only).
// Each group has an optional label; null = render items with no section header.
class _NavGroup {
  final String? label;
  final List<_NavDestination> destinations;

  const _NavGroup({this.label, required this.destinations});
}

// ── Flat destination lists (used for index mapping & non-hotel modules) ──

final _restaurantDestinations = <_NavDestination>[
  _NavDestination(label: 'Tableau de bord', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, route: AppRoutes.restaurantDashboard),
  _NavDestination(label: 'Tables', icon: Icons.table_bar_outlined, selectedIcon: Icons.table_bar, route: AppRoutes.restaurantTables),
  _NavDestination(label: 'Réservations', icon: Icons.event_seat_outlined, selectedIcon: Icons.event_seat, route: AppRoutes.restaurantReservations),
  _NavDestination(label: 'Menu', icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, route: AppRoutes.restaurantMenu),
  _NavDestination(label: 'Commandes', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, route: AppRoutes.restaurantOrders),
  _NavDestination(label: 'Liens', icon: Icons.add_link_outlined, selectedIcon: Icons.add_link, route: AppRoutes.restaurantPayLinks),
  _NavDestination(label: 'Historique', icon: Icons.history_outlined, selectedIcon: Icons.history, route: AppRoutes.restaurantOrderHistory),
  _NavDestination(label: 'Cuisine', icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, route: AppRoutes.restaurantKitchen),
  _NavDestination(label: 'Cuisine terminée', icon: Icons.check_circle_outline, selectedIcon: Icons.check_circle, route: AppRoutes.restaurantKitchenCompleted),
  _NavDestination(label: 'Inventaire', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, route: AppRoutes.restaurantInventory),
  _NavDestination(label: 'Contrôle de caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, route: AppRoutes.restaurantCashControl),
  _NavDestination(label: 'Clients', icon: Icons.people_outline, selectedIcon: Icons.people, route: AppRoutes.restaurantCustomers),
  _NavDestination(label: 'Rapports', icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, route: AppRoutes.restaurantReports),
  _NavDestination(label: 'Pointage', icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled, route: AppRoutes.restaurantTimeclock),
  _NavDestination(label: 'Paramètres', icon: Icons.settings_outlined, selectedIcon: Icons.settings, route: AppRoutes.restaurantSettings),
];

final _retailDestinations = <_NavDestination>[
  _NavDestination(label: 'Caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, route: AppRoutes.retailPos),
  _NavDestination(label: 'Produits', icon: Icons.inventory_outlined, selectedIcon: Icons.inventory, route: AppRoutes.retailProducts),
  _NavDestination(label: 'Commandes', icon: Icons.manage_search_outlined, selectedIcon: Icons.manage_search, route: AppRoutes.retailOrderHistory),
  _NavDestination(label: 'Liens', icon: Icons.add_link_outlined, selectedIcon: Icons.add_link, route: AppRoutes.retailPayLinks),
  _NavDestination(label: 'Devis', icon: Icons.request_quote_outlined, selectedIcon: Icons.request_quote, route: AppRoutes.retailQuotes),
  _NavDestination(label: 'Clients', icon: Icons.people_outline, selectedIcon: Icons.people, route: AppRoutes.retailCustomers),
  _NavDestination(label: 'Fournisseurs', icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, route: AppRoutes.retailSuppliers),
  _NavDestination(label: 'Inventaire', icon: Icons.warehouse_outlined, selectedIcon: Icons.warehouse, route: AppRoutes.retailInventory),
  _NavDestination(label: 'Contrôle de caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, route: AppRoutes.retailCashControl),
  _NavDestination(label: 'Rapports', icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, route: AppRoutes.retailReports),
  _NavDestination(label: 'Pointage', icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled, route: AppRoutes.retailTimeclock),
  _NavDestination(label: 'Tableau de bord', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, route: AppRoutes.retailDashboard),
  _NavDestination(label: 'Paramètres', icon: Icons.settings_outlined, selectedIcon: Icons.settings, route: AppRoutes.retailSettings),
];

// Hotel + Restaurant grouped navigation
final _hotelNavGroups = <_NavGroup>[
  _NavGroup(
    label: 'HÔTEL',
    destinations: [
      _NavDestination(label: 'Tableau de bord', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, route: AppRoutes.hotelDashboard),
      _NavDestination(label: 'Chambres', icon: Icons.hotel_outlined, selectedIcon: Icons.hotel, route: AppRoutes.hotelRooms),
      _NavDestination(label: 'Réservations', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, route: AppRoutes.hotelReservations),
      _NavDestination(label: 'Arrivée', icon: Icons.login_outlined, selectedIcon: Icons.login, route: AppRoutes.hotelCheckIn),
      _NavDestination(label: 'Départ', icon: Icons.logout_outlined, selectedIcon: Icons.logout, route: AppRoutes.hotelCheckOut),
      _NavDestination(label: 'Entretien', icon: Icons.cleaning_services_outlined, selectedIcon: Icons.cleaning_services, route: AppRoutes.hotelHousekeeping),
      _NavDestination(label: 'Service en chambre', icon: Icons.room_service_outlined, selectedIcon: Icons.room_service, route: AppRoutes.hotelRoomService),
      _NavDestination(label: 'Clients', icon: Icons.people_outline, selectedIcon: Icons.people, route: AppRoutes.hotelGuests),
      _NavDestination(label: 'Rapports hôtel', icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, route: AppRoutes.hotelReports),
      _NavDestination(label: 'Contrôle de caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, route: AppRoutes.hotelFrontDeskCashControl),
    ],
  ),
  _NavGroup(
    label: 'RESTAURANT',
    destinations: [
      _NavDestination(label: 'Tables', icon: Icons.table_bar_outlined, selectedIcon: Icons.table_bar, route: AppRoutes.hotelRestaurantTables),
      _NavDestination(label: 'Réservations', icon: Icons.event_seat_outlined, selectedIcon: Icons.event_seat, route: AppRoutes.hotelRestaurantReservations),
      _NavDestination(label: 'Menu', icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, route: AppRoutes.hotelRestaurantMenu),
      _NavDestination(label: 'Commandes', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, route: AppRoutes.hotelRestaurantOrders),
      _NavDestination(label: 'Liens', icon: Icons.add_link_outlined, selectedIcon: Icons.add_link, route: AppRoutes.hotelPayLinks),
      _NavDestination(label: 'Cuisine', icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, route: AppRoutes.hotelRestaurantKitchen),
      _NavDestination(label: 'Cuisine terminée', icon: Icons.check_circle_outline, selectedIcon: Icons.check_circle, route: AppRoutes.hotelRestaurantKitchenCompleted),
      _NavDestination(label: 'Facturation', icon: Icons.request_quote_outlined, selectedIcon: Icons.request_quote, route: AppRoutes.hotelRestaurantBilling),
      _NavDestination(label: 'Inventaire', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, route: AppRoutes.hotelRestaurantInventory),
      _NavDestination(label: 'Contrôle de caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, route: AppRoutes.hotelCashControl),
      _NavDestination(label: 'Rapports resto', icon: Icons.analytics_outlined, selectedIcon: Icons.analytics, route: AppRoutes.hotelRestaurantReports),
    ],
  ),
  _NavGroup(
    label: 'COMMANDES',
    destinations: [
      _NavDestination(label: 'Historique', icon: Icons.manage_search_outlined, selectedIcon: Icons.manage_search, route: AppRoutes.hotelOrderHistory),
      _NavDestination(label: 'Clients', icon: Icons.people_outline, selectedIcon: Icons.people, route: AppRoutes.hotelCustomers),
    ],
  ),
  _NavGroup(
    label: null,
    destinations: [
      _NavDestination(label: 'Pointage', icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled, route: AppRoutes.hotelTimeclock),
      _NavDestination(label: 'Paramètres', icon: Icons.settings_outlined, selectedIcon: Icons.settings, route: AppRoutes.hotelSettings),
    ],
  ),
];

// Flat version of hotel destinations (for index-based navigation)
final _hotelDestinationsFlat = _hotelNavGroups.expand((g) => g.destinations).toList();

// Mobile bottom nav items for hotel module (top 5 most-used)
final _hotelMobileDestinations = <_NavDestination>[
  _NavDestination(label: 'Tableau de bord', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, route: AppRoutes.hotelDashboard),
  _NavDestination(label: 'Chambres', icon: Icons.hotel_outlined, selectedIcon: Icons.hotel, route: AppRoutes.hotelRooms),
  _NavDestination(label: 'Tables', icon: Icons.table_bar_outlined, selectedIcon: Icons.table_bar, route: AppRoutes.hotelRestaurantTables),
  _NavDestination(label: 'Commandes', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, route: AppRoutes.hotelRestaurantOrders),
  _NavDestination(label: 'Cuisine', icon: Icons.soup_kitchen_outlined, selectedIcon: Icons.soup_kitchen, route: AppRoutes.hotelRestaurantKitchen),
];

List<_NavDestination> _fallbackNav(ActiveModule module) {
  final r = dashboardPathForModule(module);
  return [
    _NavDestination(
      label: 'Tableau de bord',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      route: r,
    ),
  ];
}

List<_NavDestination> _filterNavDestinations(
  List<_NavDestination> list,
  WidgetRef ref,
  ActiveModule module,
) {
  final perms = ref.watch(effectivePermissionsProvider);
  final role = ref.watch(staffSessionProvider.select((s) => s?.role));
  if (role == null) return list;
  final out = list
      .where(
        (d) => canAccessShellRoute(
          route: d.route,
          module: module,
          perms: perms,
          role: role,
        ),
      )
      .toList();
  return out.isEmpty ? _fallbackNav(module) : out;
}

List<_NavGroup> _filterHotelNavGroups(WidgetRef ref, ActiveModule module) {
  final perms = ref.watch(effectivePermissionsProvider);
  final role = ref.watch(staffSessionProvider.select((s) => s?.role));
  if (role == null) return _hotelNavGroups;
  final out = <_NavGroup>[];
  for (final g in _hotelNavGroups) {
    final dests = g.destinations
        .where(
          (d) => canAccessShellRoute(
            route: d.route,
            module: module,
            perms: perms,
            role: role,
          ),
        )
        .toList();
    if (dests.isEmpty) continue;
    out.add(_NavGroup(label: g.label, destinations: dests));
  }
  return out.isEmpty
      ? [
          _NavGroup(
            label: null,
            destinations: _fallbackNav(module),
          ),
        ]
      : out;
}

class AppShell extends ConsumerStatefulWidget {
  final ActiveModule module;
  final Widget child;

  const AppShell({super.key, required this.module, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  List<_NavDestination> get _rawFlatDestinations {
    switch (widget.module) {
      case ActiveModule.restaurant:
        return _restaurantDestinations;
      case ActiveModule.hotel:
        return _hotelDestinationsFlat;
      case ActiveModule.retail:
        return _retailDestinations;
    }
  }

  /// Picks the nav item whose [route] best matches [location]. Uses the **longest**
  /// matching route so e.g. `/restaurant/kitchen/completed` selects "Cuisine terminée",
  /// not "Cuisine" (which would match first with a naive prefix check).
  int _selectedIndex(String location, List<_NavDestination> list) {
    var bestIndex = 0;
    var bestLen = -1;
    for (var i = 0; i < list.length; i++) {
      final route = list[i].route;
      final matches =
          location == route || location.startsWith('$route/');
      if (matches && route.length > bestLen) {
        bestLen = route.length;
        bestIndex = i;
      }
    }
    return bestLen < 0 ? 0 : bestIndex;
  }

  void _onDestinationSelected(
    int index,
    BuildContext context,
    List<_NavDestination> flat,
  ) {
    navigateWithLoading(ref, context, flat[index].route);
  }

  String get _moduleLabel {
    switch (widget.module) {
      case ActiveModule.restaurant:
        return 'Restaurant';
      case ActiveModule.hotel:
        return 'Hôtel + restaurant';
      case ActiveModule.retail:
        return 'Détail';
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final width = MediaQuery.of(context).size.width;

    final List<_NavDestination> flatDestinations;
    final List<_NavGroup>? navGroupsFiltered;
    if (widget.module == ActiveModule.hotel) {
      navGroupsFiltered = _filterHotelNavGroups(ref, widget.module);
      flatDestinations =
          navGroupsFiltered.expand((g) => g.destinations).toList();
    } else {
      navGroupsFiltered = null;
      flatDestinations =
          _filterNavDestinations(_rawFlatDestinations, ref, widget.module);
    }

    final selectedIndex = _selectedIndex(location, flatDestinations);
    final hotelBottom = widget.module == ActiveModule.hotel
        ? _filterNavDestinations(_hotelMobileDestinations, ref, widget.module)
        : null;

    final isDesktop = width > AppConstants.tabletBreakpoint;
    final isTablet = width > AppConstants.mobileBreakpoint && width <= AppConstants.tabletBreakpoint;

    if (isDesktop) {
      return _DesktopLayout(
        destinations: flatDestinations,
        navGroups: navGroupsFiltered,
        selectedIndex: selectedIndex,
        moduleLabel: _moduleLabel,
        module: widget.module,
        onDestinationSelected: (i) =>
            _onDestinationSelected(i, context, flatDestinations),
        child: widget.child,
      );
    } else if (isTablet) {
      return _TabletLayout(
        moduleLabel: _moduleLabel,
        destinations: flatDestinations,
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) =>
            _onDestinationSelected(i, context, flatDestinations),
        child: widget.child,
      );
    } else {
      return _MobileLayout(
        module: widget.module,
        moduleLabel: _moduleLabel,
        destinations: flatDestinations,
        hotelBottomDestinations: hotelBottom,
        location: location,
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) =>
            _onDestinationSelected(i, context, flatDestinations),
        child: widget.child,
      );
    }
  }
}

// ──────────────────────────────────────────────
// Desktop Layout — full sidebar
// ──────────────────────────────────────────────
class _DesktopLayout extends ConsumerWidget {
  final List<_NavDestination> destinations;
  final List<_NavGroup>? navGroups;
  final int selectedIndex;
  final String moduleLabel;
  final ActiveModule module;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const _DesktopLayout({
    required this.destinations,
    required this.navGroups,
    required this.selectedIndex,
    required this.moduleLabel,
    required this.module,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isCollapsed = ref.watch(sidebarCollapsedProvider);

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            destinations: destinations,
            navGroups: navGroups,
            selectedIndex: selectedIndex,
            moduleLabel: moduleLabel,
            businessName: authState.businessName ?? 'BizManager Haïti',
            userName: authState.userName ?? 'Gérant',
            onDestinationSelected: onDestinationSelected,
            isCollapsed: isCollapsed,
            onToggleCollapsed: () =>
                ref.read(sidebarCollapsedProvider.notifier).state = !isCollapsed,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(moduleLabel: moduleLabel),
                const OfflineBanner(),
                Expanded(child: KeyboardScrollArea(child: LoadingOverlay(child: child))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final List<_NavDestination> destinations;
  final List<_NavGroup>? navGroups;
  final int selectedIndex;
  final String moduleLabel;
  final String businessName;
  final String userName;
  final ValueChanged<int> onDestinationSelected;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  const _Sidebar({
    required this.destinations,
    required this.navGroups,
    required this.selectedIndex,
    required this.moduleLabel,
    required this.businessName,
    required this.userName,
    required this.onDestinationSelected,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  Widget _buildNavItem(
      int globalIndex, _NavDestination dest, bool showExpandedContent) {
    final isSelected = globalIndex == selectedIndex;
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
          child: InkWell(
          onTap: () => onDestinationSelected(globalIndex),
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (_, c) {
              final show = showExpandedContent && c.maxWidth >= 90;
              return AnimatedContainer(
                duration: AppConstants.animFast,
                padding: EdgeInsets.symmetric(
                  horizontal: show ? 12 : 0,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.sidebarSelected : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: show
                    ? SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? dest.selectedIcon : dest.icon,
                              size: 20,
                              color: isSelected
                                  ? AppColors.white
                                  : AppColors.sidebarIcon,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                dest.label,
                                style: AppTextStyles.navItem(
                                  color: isSelected
                                      ? AppColors.white
                                      : AppColors.sidebarIcon,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    color: AppColors.amber,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : Center(
                        child: Icon(
                          isSelected ? dest.selectedIcon : dest.icon,
                          size: 20,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.sidebarIcon,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
    return showExpandedContent
        ? content
        : Tooltip(message: dest.label, child: content);
  }

  List<Widget> _buildNavItems(bool showExpandedContent) {
    final groups = navGroups;
    if (groups == null) {
      // Flat nav (restaurant / retail)
      return [
        for (int i = 0; i < destinations.length; i++)
          _buildNavItem(i, destinations[i], showExpandedContent),
      ];
    }

    // Grouped nav (hotel + restaurant)
    final items = <Widget>[];
    int globalIndex = 0;
    for (int g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (showExpandedContent && group.label != null) {
        if (g > 0) items.add(const SizedBox(height: 8));
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.sidebarDivider,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    group.label!,
                    style: AppTextStyles.caption(color: AppColors.sidebarSectionLabel)
                        .copyWith(fontSize: 9, letterSpacing: 1.2),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.sidebarDivider,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      for (final dest in group.destinations) {
        items.add(_buildNavItem(globalIndex, dest, showExpandedContent));
        globalIndex++;
      }
    }
    return items;
  }

  Widget _buildLogoutItem(
      BuildContext context, WidgetRef ref, bool showExpandedContent) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
          child: InkWell(
          onTap: () => endStaffSessionToPin(ref, context),
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (_, c) {
              final show = showExpandedContent && c.maxWidth >= 90;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: show ? 12 : 0,
                  vertical: 10,
                ),
                child: show
                    ? SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.logout_outlined,
                              size: 20,
                              color: AppColors.sidebarIcon,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Déconnexion',
                                style: AppTextStyles.navItem(
                                    color: AppColors.sidebarIcon),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.logout_outlined,
                          size: 20,
                          color: AppColors.sidebarIcon,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
    return showExpandedContent
        ? content
        : Tooltip(message: 'Déconnexion — retour au code PIN', child: content);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffSessionProvider);
    final displayFirstName =
        firstNameFromDisplayName(staff?.employeeName ?? userName);
    final roleSubtitle =
        staff != null ? staffRoleDisplayLabel(staff.role) : 'Gérant';

    // Sidebar width is fixed (rail vs full); do not use parent Row constraints —
    // they are unbounded horizontally, which breaks flex children inside list rows.
    final showExpandedContent = !isCollapsed;
    return AnimatedContainer(
      duration: AppConstants.animNormal,
      width: isCollapsed ? AppConstants.railWidth : AppConstants.sidebarWidth,
      color: AppColors.sidebarBackground,
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // Collapse toggle — icon only, pinned to top
          Padding(
            padding: EdgeInsets.fromLTRB(
              showExpandedContent ? 12 : 8, 8, showExpandedContent ? 12 : 8, 0,
            ),
            child: Row(
              mainAxisAlignment: showExpandedContent
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: isCollapsed ? 'Développer le menu' : 'Réduire le menu',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onToggleCollapsed,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                          size: 18,
                          color: AppColors.sidebarIcon,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Logo area
          LayoutBuilder(
            builder: (_, c) {
              final show = showExpandedContent && c.maxWidth >= 100;
              return Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  show ? 20 : 12,
                  show ? 14 : 10,
                  show ? 20 : 12,
                  show ? 10 : 6,
                ),
                child: show
                    ? Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.business_center,
                                color: AppColors.nearBlack, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'BizManager',
                              style: AppTextStyles.appName(color: AppColors.white)
                                  .copyWith(fontSize: 15),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.business_center,
                              color: AppColors.nearBlack, size: 20),
                        ),
                      ),
              );
            },
          ),
          if (showExpandedContent)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    businessName,
                    style: AppTextStyles.caption(color: AppColors.sidebarIcon),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      moduleLabel,
                      style: AppTextStyles.caption(color: AppColors.amber),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: AppColors.sidebarDivider, height: 1),
          const SizedBox(height: 8),
          // Nav items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: showExpandedContent ? 12 : 8,
                vertical: 4,
              ),
              children: [
                ..._buildNavItems(showExpandedContent),
                const SizedBox(height: 8),
                _buildLogoutItem(context, ref, showExpandedContent),
              ],
            ),
          ),
          // Bottom user section
          const Divider(color: AppColors.sidebarDivider, height: 1),
          LayoutBuilder(
            builder: (_, c) {
              final show = showExpandedContent && c.maxWidth >= 100;
              return Padding(
                padding: EdgeInsets.all(isCollapsed ? 12 : 16),
                child: show
                    ? SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 22,
                              color: AppColors.sidebarIcon,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayFirstName,
                                    style: AppTextStyles.navItem(
                                        color: AppColors.white),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    roleSubtitle,
                                    style: AppTextStyles.caption(
                                        color: AppColors.sidebarIcon),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const ConnectivityDot(
                                status: ConnectivityStatus.online),
                          ],
                        ),
                      )
                    : Tooltip(
                        message: '$displayFirstName · $roleSubtitle',
                        child: const Icon(
                          Icons.person_outline,
                          size: 22,
                          color: AppColors.sidebarIcon,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Tablet Layout — navigation rail
// ──────────────────────────────────────────────
class _TabletLayout extends ConsumerWidget {
  final String moduleLabel;
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const _TabletLayout({
    required this.moduleLabel,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final railBackground =
        isDark ? AppColors.darkSurface : AppColors.primaryBlue;

    return Scaffold(
      body: Row(
        children: [
          // NavigationRail doesn't scroll its destinations natively — when the
          // viewport is shorter than the rail's intrinsic height it overflows.
          // Wrap it in a vertically scrollable container so it always fits.
          ColoredBox(
            color: railBackground,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        backgroundColor: railBackground,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                        labelType: NavigationRailLabelType.selected,
                        selectedIconTheme: const IconThemeData(
                            color: AppColors.amber, size: 22),
                        unselectedIconTheme: IconThemeData(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.sidebarIcon,
                          size: 22,
                        ),
                        selectedLabelTextStyle:
                            AppTextStyles.navItem(color: AppColors.amber)
                                .copyWith(fontSize: 11),
                        unselectedLabelTextStyle: AppTextStyles.navItem(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.sidebarIcon,
                        ).copyWith(fontSize: 11),
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.business_center,
                                color: AppColors.nearBlack, size: 20),
                          ),
                        ),
                        destinations: destinations
                            .map((d) => NavigationRailDestination(
                                  icon: Icon(d.icon),
                                  selectedIcon: Icon(d.selectedIcon),
                                  label: Text(d.label),
                                ))
                            .toList(),
                        trailing: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IconButton(
                            icon: const Icon(Icons.logout_outlined),
                            onPressed: () => endStaffSessionToPin(ref, context),
                            tooltip: 'Déconnexion — retour au code PIN',
                            style: IconButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.coolGray
                                  : AppColors.sidebarIcon,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(moduleLabel: moduleLabel, compact: true),
                const OfflineBanner(),
                Expanded(
                  child: KeyboardScrollArea(
                    child: LoadingOverlay(child: child),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Mobile Layout — bottom navigation bar
// ──────────────────────────────────────────────
class _MobileLayout extends ConsumerWidget {
  final ActiveModule module;
  final String moduleLabel;
  final List<_NavDestination> destinations;
  /// When set (hotel), replaces [_hotelMobileDestinations] with permission-filtered list.
  final List<_NavDestination>? hotelBottomDestinations;
  final String location;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const _MobileLayout({
    required this.module,
    required this.moduleLabel,
    required this.destinations,
    this.hotelBottomDestinations,
    required this.location,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hotel module uses a curated bottom nav spanning hotel + restaurant
    final List<_NavDestination> bottomDests = module == ActiveModule.hotel
        ? (hotelBottomDestinations ?? _hotelMobileDestinations)
        : destinations.take(5).toList();

    // Longest matching route wins (same rule as sidebar — e.g. kitchen subpaths).
    var adjustedIndex = 0;
    var bestLen = -1;
    for (var i = 0; i < bottomDests.length; i++) {
      final route = bottomDests[i].route;
      final matches =
          location == route || location.startsWith('$route/');
      if (matches && route.length > bestLen) {
        bestLen = route.length;
        adjustedIndex = i;
      }
    }

    return Scaffold(
      drawer: _MobileSideMenu(
        destinations: destinations,
        selectedRoute: location,
        onSelected: (route) {
          Navigator.of(context).pop();
          navigateWithLoading(ref, context, route);
        },
      ),
      body: Builder(
        builder: (bodyContext) => Column(
          children: [
            _TopBar(
              moduleLabel: moduleLabel,
              compact: true,
              onMenu: () => Scaffold.of(bodyContext).openDrawer(),
            ),
            const OfflineBanner(),
            Expanded(
              child: KeyboardScrollArea(child: LoadingOverlay(child: child)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: adjustedIndex,
        onDestinationSelected: (i) => navigateWithLoading(ref, context, bottomDests[i].route),
        destinations: bottomDests.map((d) => NavigationDestination(
          icon: Icon(d.icon),
          selectedIcon: Icon(d.selectedIcon),
          label: d.label,
        )).toList(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Top Bar (Desktop only)
// ──────────────────────────────────────────────
class _TopBar extends ConsumerWidget {
  final String moduleLabel;
  /// Tighter padding / name width for tablet + mobile headers.
  final bool compact;

  const _TopBar({
    required this.moduleLabel,
    this.compact = false,
    this.onMenu,
  });

  final VoidCallback? onMenu;

  void _showNotificationsSheet(BuildContext context, bool isDark) {
    final notifications = [
      (Icons.table_restaurant_outlined, 'Table 5 en attente depuis 25 min', 'il y a 2 min', AppColors.boldRed),
      (Icons.inventory_2_outlined, 'Stock bas : Rhum Barbancourt (3 restants)', 'il y a 10 min', AppColors.amber),
      (Icons.hotel_outlined, 'Chambre 204 — départ en retard', 'il y a 30 min', AppColors.amber),
      (Icons.payment_outlined, 'Paiement confirmé — 4 500 HTG', 'il y a 1 h', AppColors.deepGreen),
      (Icons.person_outline, 'Nouvelle réservation : Dupont · 1 mars', 'il y a 2 h', AppColors.primaryBlue),
    ];

    showAppBottomSheet(
      context: context,
      child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppConstants.spacing24, AppConstants.spacing16, AppConstants.spacing16, AppConstants.spacing8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: AppTextStyles.h2(
                          color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tout marquer comme lu'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final n = notifications[i];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: n.$4.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(n.$1, color: n.$4, size: 20),
                    ),
                    title: Text(n.$2,
                        style: AppTextStyles.body(
                            color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
                    subtitle: Text(n.$3, style: AppTextStyles.caption()),
                    trailing: i < 3
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final staff = ref.watch(staffSessionProvider);
    final displayFirstName = firstNameFromDisplayName(
      staff?.employeeName ?? authState.userName,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormatter.topBarDate();
    final online = ref.watch(deviceSessionProvider.select((s) => s.online));

    return Container(
      height: compact ? 56 : 64,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : AppConstants.spacing24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE),
          ),
        ),
      ),
      child: Row(
        children: [
          if (onMenu != null)
            IconButton(
              tooltip: 'Menu',
              onPressed: onMenu,
              icon: Icon(
                Icons.menu,
                color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        authState.businessName ?? 'BizManager Haïti',
                        style: AppTextStyles.h3(
                          color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        '·',
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.coolGray : AppColors.darkGray,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          moduleLabel,
                          style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(dateStr, style: AppTextStyles.caption()),
              ],
            ),
          ),
          ConnectivityDot(
            status: online
                ? ConnectivityStatus.online
                : ConnectivityStatus.offline,
          ),
          const SizedBox(width: AppConstants.spacing16),
          _TopBarAction(
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            onTap: () => ref.read(themeProvider.notifier).toggleOverride(),
          ),
          const SizedBox(width: AppConstants.spacing8),
          _TopBarAction(
            icon: Icons.notifications_outlined,
            onTap: () => _showNotificationsSheet(context, isDark),
            badge: 3,
          ),
          const SizedBox(width: AppConstants.spacing8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? 140 : 220,
            ),
            child: Text(
              displayFirstName,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          IconButton(
            onPressed: () => endStaffSessionToPin(ref, context),
            icon: Icon(
              Icons.logout_rounded,
              size: compact ? 22 : 24,
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
            tooltip: 'Déconnexion — retour au code PIN',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }

}

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int? badge;

  const _TopBarAction({required this.icon, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon,
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
            size: 22,
          ),
          onPressed: onTap,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        if (badge != null && badge! > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.boldRed,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MobileSideMenu extends ConsumerWidget {
  const _MobileSideMenu({
    required this.destinations,
    required this.selectedRoute,
    required this.onSelected,
  });

  final List<_NavDestination> destinations;
  final String selectedRoute;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final canvas = isDark ? AppColors.darkBackground : const Color(0xFFF2F2F7);
    final card = isDark ? AppColors.darkSurface : AppColors.white;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : const Color(0xFF8E8E93);
    final hairline = isDark ? AppColors.darkBorder : const Color(0xFFE5E5EA);
    final business = (auth.businessName ?? '').isEmpty
        ? 'Caisse détail'
        : auth.businessName!;
    final rows = <_SideMenuRowData>[
      for (final destination in destinations)
        _SideMenuRowData(
          icon: destination.icon,
          label: destination.label,
          selected: selectedRoute == destination.route,
          onTap: () => onSelected(destination.route),
        ),
      _SideMenuRowData(
        icon: Icons.laptop_mac_outlined,
        label: 'Appareils connectés',
        selected: selectedRoute == AppRoutes.devices,
        onTap: () {
          Navigator.of(context).pop();
          context.push(AppRoutes.devices);
        },
      ),
    ];

    return Drawer(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business,
                    style: AppTextStyles.h3(color: ink),
                  ),
                  if ((auth.userName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      auth.userName!,
                      style: AppTextStyles.caption(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      _SideMenuRow(
                        data: rows[i],
                        ink: ink,
                        chevron: muted,
                      ),
                      if (i != rows.length - 1)
                        Divider(
                          height: 1,
                          thickness: 0.6,
                          indent: 54,
                          color: hairline,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenuRowData {
  const _SideMenuRowData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
}

class _SideMenuRow extends StatelessWidget {
  const _SideMenuRow({
    required this.data,
    required this.ink,
    required this.chevron,
  });

  final _SideMenuRowData data;
  final Color ink;
  final Color chevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(data.icon, size: 22, color: ink),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  data.label,
                  style: AppTextStyles.body(color: ink).copyWith(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight:
                        data.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: chevron),
            ],
          ),
        ),
      ),
    );
  }
}

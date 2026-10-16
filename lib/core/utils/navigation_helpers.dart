import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';

/// Default shell home for the active business module.
String dashboardPathForModule(ActiveModule module) {
  switch (module) {
    case ActiveModule.restaurant:
      return AppRoutes.restaurantDashboard;
    case ActiveModule.hotel:
      return AppRoutes.hotelDashboard;
    case ActiveModule.retail:
      return AppRoutes.retailDashboard;
  }
}

/// Shows the loading spinner over the content area, waits one frame for the
/// overlay to paint, then performs the navigation. The spinner is dismissed
/// after a short delay so the new page is revealed cleanly.
Future<void> navigateWithLoading(WidgetRef ref, BuildContext context, String path) async {
  ref.read(loadingProvider.notifier).state = true;

  // Let the overlay paint before the route swap.
  await Future.delayed(const Duration(milliseconds: 50));

  if (context.mounted) context.go(path);

  // Keep spinner visible while the new page settles, then dismiss.
  await Future.delayed(const Duration(milliseconds: 400));
  ref.read(loadingProvider.notifier).state = false;
}

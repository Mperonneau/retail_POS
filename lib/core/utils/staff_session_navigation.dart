import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import '../providers/staff_session_provider.dart';

/// Ends Tier 2 (staff PIN) and returns to the PIN screen. Tier 1 auth stays.
void endStaffSessionToPin(WidgetRef ref, BuildContext context) {
  ref.read(staffSessionProvider.notifier).clear();
  if (context.mounted) context.go(AppRoutes.pin);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/staff_session_provider.dart';

/// Clears Tier 2 (staff PIN) then Tier 1 (business login).
void logoutCompletely(WidgetRef ref) {
  ref.read(staffSessionProvider.notifier).clear();
  ref.read(authProvider.notifier).logout();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Desktop: `true` = narrow rail (default); user expands to full width via toggle.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => true);

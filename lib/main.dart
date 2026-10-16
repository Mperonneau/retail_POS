import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_router.dart';
import 'core/providers/staff_session_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/widgets/app_notification_banner.dart';
import 'core/widgets/app_update_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: BizManagerApp()));
}

class BizManagerApp extends ConsumerWidget {
  const BizManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Only subscribe to presence of staff session — not lastActivityAt — or every
    // tap rebuilds MaterialApp and breaks gestures/scroll.
    final hasStaffSession =
        ref.watch(staffSessionProvider.select((s) => s != null));

    return MaterialApp.router(
      title: 'Retail POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: AppScrollBehavior(),
      routerConfig: router,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final body = !hasStaffSession
            ? content
            : Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) =>
                        ref.read(staffSessionProvider.notifier).recordActivity(),
                    child: content,
                  ),
                  const AppNotificationModal(),
                ],
              );
        return AppUpdateHost(child: body);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/navigation/app_router.dart';
import 'core/providers/staff_session_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/browser_chrome.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/widgets/app_notification_banner.dart';
import 'core/widgets/app_update_banner.dart';
import 'core/theme/app_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');
  try {
    final font = rootBundle.load('assets/fonts/material_icons_full.otf');
    await Future.wait([
      (FontLoader('MaterialIcons')..addFont(font)).load(),
      (FontLoader(kFullIconFamily)..addFont(font)).load(),
    ]);
  } catch (_) {
    // Icons may be blank, but the register must still open.
  }
  runApp(const ProviderScope(child: BizManagerApp()));
}

class BizManagerApp extends ConsumerWidget {
  const BizManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final headerColor =
        themeMode == ThemeMode.dark ? AppColors.darkSurface : AppColors.white;
    paintBrowserChrome(headerColor);
    // Only subscribe to presence of staff session — not lastActivityAt — or every
    // tap rebuilds MaterialApp and breaks gestures/scroll.
    final hasStaffSession =
        ref.watch(staffSessionProvider.select((s) => s != null));

    return MaterialApp.router(
      title: 'Caisse détail',
      // On the web this becomes theme-color, the strip above the top bar.
      color: headerColor,
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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

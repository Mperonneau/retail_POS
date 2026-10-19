import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_scroll_behavior.dart';
import 'package:retail_pos/core/theme/app_theme.dart';

import 'screens/home_page.dart';
import 'screens/request_page.dart';
import 'screens/shop_page.dart';

Future<void> main() async {
  usePathUrlStrategy();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');
  runApp(const StorefrontApp());
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/r/:id',
      builder: (_, state) => RequestPage(requestId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/:slug',
      builder: (_, state) => ShopPage(slug: state.pathParameters['slug']!),
    ),
  ],
  errorBuilder: (_, _) => const HomePage(),
);

class StorefrontApp extends StatelessWidget {
  const StorefrontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Vitrine',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light.copyWith(scaffoldBackgroundColor: AppColors.warmOffWhite),
      scrollBehavior: AppScrollBehavior(),
      routerConfig: _router,
    );
  }
}

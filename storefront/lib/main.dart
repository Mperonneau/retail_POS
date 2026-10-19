import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_scroll_behavior.dart';
import 'package:retail_pos/core/theme/app_theme.dart';

import 'session.dart';
import 'favorites.dart';
import 'shell.dart';
import 'screens/about_page.dart';
import 'screens/cart_page.dart';
import 'screens/favorites_page.dart';
import 'screens/help_page.dart';
import 'screens/home_page.dart';
import 'screens/login_page.dart';
import 'screens/orders_page.dart';
import 'screens/profile_page.dart';
import 'screens/request_page.dart';
import 'screens/shop_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');
  await Session.instance.restore();
  await Favorites.instance.restore();
  runApp(const StorefrontApp());
}

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (_, _, child) => StorefrontShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomePage()),
        GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
        GoRoute(path: '/favorites', builder: (_, _) => const FavoritesPage()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(path: '/cart', builder: (_, _) => const CartPage()),
        GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
        GoRoute(path: '/help', builder: (_, _) => const HelpPage()),
        GoRoute(
          path: '/r/:id',
          builder: (_, state) => RequestPage(requestId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/:slug',
          builder: (_, state) => ShopPage(slug: state.pathParameters['slug']!),
        ),
      ],
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

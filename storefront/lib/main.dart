import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_scroll_behavior.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/core/widgets/app_update_banner.dart';

import 'session.dart';
import 'favorites.dart';
import 'page.dart';
import 'shell.dart';
import 'screens/about_page.dart';
import 'screens/cart_page.dart';
import 'screens/favorites_page.dart';
import 'screens/help_page.dart';
import 'screens/home_page.dart';
import 'screens/login_code_page.dart';
import 'screens/login_name_page.dart';
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
        GoRoute(
          path: '/',
          pageBuilder: (_, state) => storePage(state, const HomePage()),
        ),
        GoRoute(
          path: '/orders',
          pageBuilder: (_, state) => storePage(state, const OrdersPage()),
        ),
        GoRoute(
          path: '/favorites',
          pageBuilder: (_, state) => storePage(state, const FavoritesPage()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (_, state) => storePage(state, const ProfilePage()),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (_, state) => storePage(state, const LoginPage()),
        ),
        GoRoute(
          path: '/login/code',
          pageBuilder: (_, state) => storePage(state, const LoginCodePage()),
        ),
        GoRoute(
          path: '/login/profil',
          pageBuilder: (_, state) => storePage(state, const LoginNamePage()),
        ),
        GoRoute(
          path: '/cart',
          pageBuilder: (_, state) => storePage(state, const CartPage()),
        ),
        GoRoute(
          path: '/about',
          pageBuilder: (_, state) => storePage(state, const AboutPage()),
        ),
        GoRoute(
          path: '/help',
          pageBuilder: (_, state) => storePage(state, const HelpPage()),
        ),
        GoRoute(
          path: '/r/:id',
          pageBuilder: (_, state) => storePage(
            state,
            RequestPage(requestId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/:slug',
          pageBuilder: (_, state) =>
              storePage(state, ShopPage(slug: state.pathParameters['slug']!)),
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
      theme: AppTheme.light.copyWith(
        scaffoldBackgroundColor: AppColors.warmOffWhite,
      ),
      scrollBehavior: AppScrollBehavior(),
      routerConfig: _router,
      builder: (context, child) => AppUpdateHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

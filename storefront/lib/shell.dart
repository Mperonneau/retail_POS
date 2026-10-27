import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

import 'cart.dart';
import 'session.dart';

/// Top bar and floating menu shared by the vitrine, like the Tabkreyol shell.
class StorefrontShell extends StatelessWidget {
  const StorefrontShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final bare = path.startsWith('/r/');
    if (bare) return child;
    return Scaffold(
      backgroundColor: AppColors.warmOffWhite,
      appBar: const StorefrontTopBar(),
      body: Stack(
        children: [
          child,
          ListenableBuilder(
            listenable: appCart,
            builder: (context, _) => Positioned(
              right: 16,
              bottom: appCart.isEmpty ? 24 : 100,
              child: const _FloatingMenu(),
            ),
          ),
        ],
      ),
    );
  }
}

class StorefrontTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StorefrontTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    Color tone(String target) =>
        path == target ? AppColors.primaryBlue : AppColors.nearBlack;
    return AppBar(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: 56,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Boutiques',
              color: tone('/'),
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.storefront_outlined),
            ),
            Text(
              'Vitrine',
              style: AppTextStyles.h2(color: AppColors.primaryBlue).copyWith(fontSize: 18),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Mes commandes',
              color: tone('/orders'),
              onPressed: () => context.go('/orders'),
              icon: const Icon(Icons.receipt_long_outlined),
            ),
            IconButton(
              tooltip: 'Favoris',
              color: tone('/favorites'),
              onPressed: () => context.go('/favorites'),
              icon: const Icon(Icons.favorite_border),
            ),
            ListenableBuilder(
              listenable: appCart,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Panier',
                    color: tone('/cart'),
                    onPressed: () => context.go('/cart'),
                    icon: const Icon(Icons.shopping_bag_outlined),
                  ),
                  if (appCart.count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${appCart.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: Session.instance,
              builder: (context, _) => IconButton(
                tooltip: 'Profil',
                color: tone('/profile'),
                onPressed: () => context.go('/profile'),
                icon: Icon(
                  Session.instance.isLoggedIn
                      ? Icons.person_rounded
                      : Icons.person_outline_rounded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingMenu extends StatefulWidget {
  const _FloatingMenu();

  @override
  State<_FloatingMenu> createState() => _FloatingMenuState();
}

class _FloatingMenuState extends State<_FloatingMenu> {
  bool _open = false;

  static const _items = [
    (label: 'Accueil', icon: Icons.storefront_outlined, path: '/'),
    (label: 'Commandes', icon: Icons.receipt_long_outlined, path: '/orders'),
    (label: 'Favoris', icon: Icons.favorite_border, path: '/favorites'),
    (label: 'Profil', icon: Icons.person_outline_rounded, path: '/profile'),
    (label: 'Panier', icon: Icons.shopping_bag_outlined, path: '/cart'),
    (label: 'À propos', icon: Icons.info_outline_rounded, path: '/about'),
    (label: 'Aide', icon: Icons.help_outline_rounded, path: '/help'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_open)
            for (final item in _items) ...[
              _MenuChip(
                label: item.label,
                icon: item.icon,
                onTap: () {
                  setState(() => _open = false);
                  final here = GoRouterState.of(context).uri.path;
                  if (here != item.path) context.go(item.path);
                },
              ),
              const SizedBox(height: 8),
            ],
          FloatingActionButton.small(
            heroTag: 'vitrine-menu',
            backgroundColor: AppColors.nearBlack,
            foregroundColor: AppColors.white,
            tooltip: 'Menu',
            onPressed: () => setState(() => _open = !_open),
            child: Icon(_open ? Icons.close_rounded : Icons.menu_rounded),
          ),
        ],
      ),
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.nearBlack,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.white, size: 18),
              const SizedBox(width: 8),
              Text(label, style: AppTextStyles.body(color: AppColors.white).copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

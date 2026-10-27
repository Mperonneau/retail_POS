import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

import '../favorites.dart';
import '../widgets.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Favorites.instance,
      builder: (context, _) {
        final shops = Favorites.instance.shops;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            Text('Favoris', style: AppTextStyles.h1(color: AppColors.nearBlack)),
            const SizedBox(height: 4),
            Text(
              'Les boutiques que vous gardez, avec ou sans compte.',
              style: AppTextStyles.body(color: AppColors.darkGray),
            ),
            const SizedBox(height: 16),
            if (shops.isEmpty)
              const SizedBox(
                height: 360,
                child: MessageView(
                icon: Icons.favorite_border,
                title: 'Aucun favori',
                message: 'Touchez le cœur sur une boutique pour la retrouver ici.',
              ),
              )
            else
              for (final shop in shops)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(shop.name, style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 16)),
                      subtitle: Text(
                        shop.place.isEmpty ? 'Boutique' : shop.place,
                        style: AppTextStyles.caption(),
                      ),
                      trailing: IconButton(
                        tooltip: 'Retirer',
                        onPressed: () => Favorites.instance.toggle(shop),
                        icon: const Icon(Icons.favorite_rounded, color: AppColors.boldRed),
                      ),
                      onTap: () => context.go('/${shop.slug}'),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

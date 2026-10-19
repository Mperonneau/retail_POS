import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';

import '../api.dart';
import '../cart.dart';
import '../money.dart';
import '../widgets.dart';
import 'cart_sheet.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appCart,
      builder: (context, _) {
        final cart = appCart;
        if (cart.isEmpty || cart.shopSlug == null) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            children: const [
              SizedBox(
                height: 360,
                child: MessageView(
                icon: Icons.shopping_bag_outlined,
                title: 'Panier vide',
                message: 'Ajoutez des articles depuis une boutique. Le panier reste ici le temps de votre visite.',
              ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            Text('Panier', style: AppTextStyles.h1(color: AppColors.nearBlack)),
            const SizedBox(height: 4),
            Text(cart.shopName, style: AppTextStyles.body(color: AppColors.darkGray)),
            const SizedBox(height: 16),
            for (final line in cart.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    title: Text(line.product.name),
                    subtitle: Text(
                      [
                        if (line.optionsLabel.isNotEmpty) line.optionsLabel,
                        '${line.quantity} × ${Money.usdFromHtg(line.unitHtg, cart.usdRate)}',
                      ].join(' · '),
                    ),
                    trailing: Text(Money.usdFromHtg(line.totalHtg, cart.usdRate)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Total ${Money.usdFromHtg(cart.totalHtg, cart.usdRate)}',
              style: AppTextStyles.h2(color: AppColors.nearBlack),
            ),
            Text(Money.htg(cart.totalHtg), style: AppTextStyles.caption()),
            const SizedBox(height: 16),
            AppButton(
              label: 'Commander ou demander un devis',
              onPressed: () => _finish(context),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Retour à la boutique',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go('/${cart.shopSlug}'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finish(BuildContext context) async {
    final slug = appCart.shopSlug;
    if (slug == null) return;
    try {
      final shop = await StorefrontApi().shop(slug);
      if (!context.mounted) return;
      await showCartSheet(context, shop: shop, cart: appCart, api: StorefrontApi());
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message, error: true);
    }
  }
}

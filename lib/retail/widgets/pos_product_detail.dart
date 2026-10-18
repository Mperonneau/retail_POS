import 'package:flutter/material.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_close_button.dart';
import '../models/product_option.dart';
import '../models/retail_cart_entry.dart';

/// Register product page: description, price, stock, options, and add to cart.
class PosProductDetail extends StatelessWidget {
  const PosProductDetail({
    super.key,
    required this.product,
    required this.cartLines,
    required this.onAdd,
    required this.onDecrementLine,
    required this.onClose,
    this.stockWarning,
  });

  final MockProduct product;
  final List<RetailCartEntry> cartLines;
  final VoidCallback onAdd;
  final ValueChanged<RetailCartEntry> onDecrementLine;
  final VoidCallback onClose;
  final String? stockWarning;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final description = product.description.trim();

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacing24,
              AppConstants.spacing16,
              AppConstants.spacing12,
              AppConstants.spacing12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTextStyles.h2(color: ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.category,
                        style: AppTextStyles.caption(color: muted),
                      ),
                    ],
                  ),
                ),
                AppCloseButton(onPressed: onClose),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing24,
                AppConstants.spacing16,
                AppConstants.spacing24,
                AppConstants.spacing16,
              ),
              children: [
                Text(
                  CurrencyFormatter.local(context, product.sellingPriceHtg),
                  style: AppTextStyles.h2(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                ),
                if (product.discountPercent > 0) ...[
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: AppTextStyles.caption(color: muted),
                      children: [
                        TextSpan(
                          text: CurrencyFormatter.local(
                            context,
                            product.priceHtg,
                          ),
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        TextSpan(text: '  ·  −${product.discountPercent} %'),
                      ],
                    ),
                  ),
                ],
                if (CurrencyFormatter.usdEquivalentOrNull(
                      context,
                      product.sellingPriceHtg,
                    )
                    case final usd?) ...[
                  const SizedBox(height: 2),
                  Text(usd, style: AppTextStyles.caption(color: muted)),
                ],
                const SizedBox(height: AppConstants.spacing16),
                _SectionLabel(label: 'Stock', color: muted),
                const SizedBox(height: 4),
                Text(
                  _stockLabel(product),
                  style: AppTextStyles.body(
                    color: product.isLowStock ? AppColors.amber : ink,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                if (product.trackStock) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Stock bas à partir de ${product.minStock}',
                    style: AppTextStyles.caption(color: muted),
                  ),
                ],
                const SizedBox(height: AppConstants.spacing16),
                _SectionLabel(label: 'Description', color: muted),
                const SizedBox(height: 4),
                Text(
                  description.isEmpty ? 'Aucune description.' : description,
                  style: AppTextStyles.body(
                    color: description.isEmpty ? muted : ink,
                  ),
                ),
                if (product.barcode != null &&
                    product.barcode!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  _SectionLabel(label: 'Code-barres', color: muted),
                  const SizedBox(height: 4),
                  Text(
                    product.barcode!.trim(),
                    style: AppTextStyles.body(color: ink),
                  ),
                ],
                if (product.options.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  _SectionLabel(label: 'Options', color: muted),
                  const SizedBox(height: AppConstants.spacing8),
                  for (final group in product.options) ...[
                    _OptionGroupBlock(group: group, ink: ink, muted: muted),
                    const SizedBox(height: AppConstants.spacing12),
                  ],
                ],
                if (cartLines.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  _SectionLabel(label: 'Dans le panier', color: muted),
                  const SizedBox(height: AppConstants.spacing8),
                  for (final line in cartLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.options.isEmpty
                                  ? 'Quantité'
                                  : line.options.map((o) => o.name).join(', '),
                              style: AppTextStyles.body(color: ink),
                            ),
                          ),
                          Text(
                            '${line.quantity}',
                            style: AppTextStyles.body(color: ink).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _QtyButton(
                            icon: Icons.remove,
                            background: AppColors.boldRed.withValues(alpha: 0.1),
                            foreground: AppColors.boldRed,
                            onTap: () => onDecrementLine(line),
                          ),
                        ],
                      ),
                    ),
                ],
                if (stockWarning != null) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  Text(
                    stockWarning!,
                    style: AppTextStyles.caption(color: AppColors.boldRed),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacing24,
              AppConstants.spacing12,
              AppConstants.spacing24,
              AppConstants.spacing16,
            ),
            child: AppButton(
              label: 'Ajouter au panier',
              icon: Icons.add,
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.caption(color: color).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _OptionGroupBlock extends StatelessWidget {
  const _OptionGroupBlock({
    required this.group,
    required this.ink,
    required this.muted,
  });

  final ProductOptionGroup group;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final rule = group.multiple ? 'Plusieurs choix' : 'Un seul choix';
    final required = group.required ? 'Obligatoire' : 'Facultatif';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.name,
          style: AppTextStyles.body(color: ink).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '$rule · $required',
          style: AppTextStyles.caption(color: muted),
        ),
        const SizedBox(height: 4),
        for (final choice in group.choices)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              choice.priceDeltaHtg == 0
                  ? choice.name
                  : '${choice.name} · +${CurrencyFormatter.local(context, choice.priceDeltaHtg)}',
              style: AppTextStyles.body(color: ink),
            ),
          ),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: foreground),
      ),
    );
  }
}

String _stockLabel(MockProduct product) {
  if (!product.trackStock) return 'Stock non suivi';
  final n = product.stockQuantity;
  final unit = switch (product.stockUnit) {
    'kg' => 'kg',
    'L' => 'L',
    'paquet' => n == 1 ? 'paquet' : 'paquets',
    _ => n == 1 ? 'unité' : 'unités',
  };
  return '$n $unit';
}

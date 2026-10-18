import 'package:flutter/material.dart';

import '../payments/card_charge_pricing.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';

/// Order, shop fee (1.5% + $1), Stripe fee, and the amount the payer settles.
class CardFeeBreakdown extends StatelessWidget {
  const CardFeeBreakdown({
    super.key,
    required this.pricing,
    required this.isDark,
    this.orderLocalLabel,
  });

  final CardChargePricing pricing;
  final bool isDark;
  final String? orderLocalLabel;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final text = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          'Vente',
          orderLocalLabel == null
              ? CurrencyFormatter.usd(pricing.orderUsd)
              : '$orderLocalLabel  ·  ${CurrencyFormatter.usd(pricing.orderUsd)}',
          muted,
          text,
        ),
        const SizedBox(height: 6),
        _row(
          'Frais 1,5 % + 1 \$',
          CurrencyFormatter.usd(pricing.platformFeeUsd),
          muted,
          text,
        ),
        const SizedBox(height: 6),
        _row(
          'Frais Stripe',
          CurrencyFormatter.usd(pricing.stripeFeeUsd),
          muted,
          text,
        ),
        const SizedBox(height: 8),
        _row(
          'Le payeur règle',
          CurrencyFormatter.usd(pricing.totalUsd),
          muted,
          isDark ? AppColors.skyBlue : AppColors.primaryBlue,
          emphasize: true,
        ),
      ],
    );
  }

  Widget _row(
    String label,
    String value,
    Color muted,
    Color valueColor, {
    bool emphasize = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTextStyles.caption(color: muted)),
        ),
        Text(
          value,
          style: emphasize
              ? AppTextStyles.price(color: valueColor)
              : AppTextStyles.body(color: valueColor),
        ),
      ],
    );
  }
}

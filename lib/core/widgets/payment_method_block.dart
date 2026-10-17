import 'package:flutter/material.dart';

import '../models/order_history.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Last 4 digits for card / MonCash phone / credit account (digits only or any string — non-digits stripped).
String? formatPaymentMaskedSuffix(
  PaymentMethodType method,
  String? raw,
) {
  if (raw == null || raw.trim().isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  final four = digits.length <= 4
      ? digits
      : digits.substring(digits.length - 4);
  return switch (method) {
    PaymentMethodType.card => '•••• $four',
    PaymentMethodType.moncash => '•••• $four',
    PaymentMethodType.credit => '•••• $four',
    PaymentMethodType.cash => null,
    PaymentMethodType.paymentLink => '•••• $four',
  };
}

/// Colored chip for MonCash / Card / Cash / Credit (receipt & order detail).
class PaymentMethodChip extends StatelessWidget {
  final PaymentMethodType method;

  const PaymentMethodChip({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (method) {
      PaymentMethodType.moncash => (
          'MonCash',
          AppColors.amber,
          Icons.phone_android_outlined,
        ),
      PaymentMethodType.card => (
          'Carte',
          AppColors.primaryBlue,
          Icons.credit_card_outlined,
        ),
      PaymentMethodType.cash => (
          'Espèces',
          AppColors.deepGreen,
          Icons.payments_outlined,
        ),
      PaymentMethodType.credit => (
          'Crédit',
          AppColors.boldRed,
          Icons.account_balance_wallet_outlined,
        ),
      PaymentMethodType.paymentLink => (
          'Lien de paiement',
          const Color(0xFF7C3AED),
          Icons.link_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption(color: color)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Method chip plus masked last-four line when applicable (below charges section).
class PaymentMethodBlock extends StatelessWidget {
  final bool isDark;
  final PaymentMethodType paymentMethod;
  final String? paymentLastFour;

  const PaymentMethodBlock({
    super.key,
    required this.isDark,
    required this.paymentMethod,
    this.paymentLastFour,
  });

  @override
  Widget build(BuildContext context) {
    final suffix =
        formatPaymentMaskedSuffix(paymentMethod, paymentLastFour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaymentMethodChip(method: paymentMethod),
        if (suffix != null) ...[
          const SizedBox(height: 6),
          Text(
            suffix,
            style: AppTextStyles.body(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
          ),
        ],
      ],
    );
  }
}

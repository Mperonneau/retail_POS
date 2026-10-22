import 'package:flutter/material.dart';

import '../models/order_history.dart';
import '../models/retail_check_payment.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Last 4 digits for card / MonCash phone / credit account (digits only or any string — non-digits stripped).
String? formatPaymentMaskedSuffix(PaymentMethodType method, String? raw) {
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
    PaymentMethodType.check => null,
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
      PaymentMethodType.check => (
        'Chèque',
        const Color(0xFF0F766E),
        Icons.account_balance_outlined,
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
            style: AppTextStyles.caption(
              color: color,
            ).copyWith(fontWeight: FontWeight.w600),
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
  final RetailCheckPayment? check;

  const PaymentMethodBlock({
    super.key,
    required this.isDark,
    required this.paymentMethod,
    this.paymentLastFour,
    this.check,
  });

  @override
  Widget build(BuildContext context) {
    final suffix = formatPaymentMaskedSuffix(paymentMethod, paymentLastFour);
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
        if (check != null) ...[
          const SizedBox(height: 10),
          CheckPaymentSummary(check: check!, isDark: isDark),
        ],
      ],
    );
  }
}

/// Number, bank, drawer, date, and photo recorded with a check payment.
class CheckPaymentSummary extends StatelessWidget {
  final RetailCheckPayment check;
  final bool isDark;

  const CheckPaymentSummary({
    super.key,
    required this.check,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final photo = check.imageBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('N° chèque', check.number, ink, muted),
        _line('Banque', check.bank, ink, muted),
        _line('Tireur', check.payerName, ink, muted),
        _line(
          'Date',
          '${check.date.day.toString().padLeft(2, '0')}/'
              '${check.date.month.toString().padLeft(2, '0')}/'
              '${check.date.year}',
          ink,
          muted,
        ),
        if (photo != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            key: const Key('check-payment-photo'),
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: isDark
                  ? AppColors.darkBackground
                  : const Color(0xFFF4F4F4),
              child: Image.memory(
                photo,
                height: 160,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      'Photo du chèque enregistrée',
                      style: AppTextStyles.caption(color: muted),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(String label, String value, Color ink, Color muted) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: AppTextStyles.caption(color: muted)),
          ),
          Expanded(
            child: Text(shown, style: AppTextStyles.body(color: ink)),
          ),
        ],
      ),
    );
  }
}

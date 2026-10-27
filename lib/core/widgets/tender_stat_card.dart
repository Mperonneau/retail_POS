import 'package:flutter/material.dart';

import '../models/cash_control.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import 'app_card.dart';

IconData paymentTenderIcon(PaymentTender t) {
  switch (t) {
    case PaymentTender.cashHtg:
      return Icons.payments_outlined;
    case PaymentTender.cashUsd:
      return Icons.attach_money;
    case PaymentTender.moncash:
      return Icons.phone_android;
    case PaymentTender.card:
      return Icons.credit_card;
    case PaymentTender.check:
      return Icons.receipt_long;
  }
}

Color paymentTenderColor(PaymentTender t, {required bool isDark}) {
  return switch (t) {
    PaymentTender.cashHtg =>
      isDark ? AppColors.skyBlue : AppColors.primaryBlue,
    PaymentTender.cashUsd => AppColors.deepGreen,
    PaymentTender.moncash => const Color(0xFF00A651),
    PaymentTender.card => AppColors.amber,
    PaymentTender.check => isDark ? AppColors.coolGray : AppColors.darkGray,
  };
}

/// Tender card showing session net + Add movement / Details actions.
class TenderStatCard extends StatelessWidget {
  const TenderStatCard({
    super.key,
    required this.tender,
    required this.netHtg,
    required this.netUsd,
    required this.isDark,
    required this.onAddMovement,
    required this.onDetails,
  });

  final PaymentTender tender;

  /// Net in HTG (used for all tenders except cashUsd).
  final double netHtg;

  /// Net in USD (used for cashUsd display).
  final double netUsd;

  final bool isDark;
  final VoidCallback onAddMovement;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final color = paymentTenderColor(tender, isDark: isDark);
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;
    final divColor =
        isDark ? AppColors.darkBorder : const Color(0xFFE8E8EE);

    // Dollars stay dollars. Card is always USD. Gourdes stay gourdes.
    final amountStr = tenderUsesUsd(tender)
        ? CurrencyFormatter.usd(netUsd)
        : CurrencyFormatter.local(context, netHtg);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  // ── Icon + label ─────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          paymentTenderIcon(tender),
                          size: 15,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tender.label,
                          style: AppTextStyles.caption(color: textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── Amount ────────────────────────────────────────────────
                  Text(
                    amountStr,
                    style: AppTextStyles.statNumber(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ).copyWith(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Net (session)',
                    style: AppTextStyles.caption(color: textSecondary)
                        .copyWith(fontSize: 10),
                  ),

                  const SizedBox(height: 3),
                  Divider(height: 1, color: divColor),
                  const SizedBox(height: 3),

                  // ── Action buttons ───────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onAddMovement,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 13, color: AppColors.amber),
                              const SizedBox(width: 3),
                              Text(
                                'Ajouter',
                                style: AppTextStyles.caption(
                                        color: AppColors.amber)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 14,
                        color: divColor,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: onDetails,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.list_alt_rounded,
                                  size: 13, color: color),
                              const SizedBox(width: 3),
                              Text(
                                'Détails',
                                style: AppTextStyles.caption(color: color)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import '../utils/order_bill_estimate.dart';
import 'app_close_button.dart';

// ── Standalone helper — call from any widget ──────────────────────────────────

/// Opens the prepaid detail bottom-sheet from any context.
/// [confirmedPaid] = staff has confirmed the bill as paid.
void showPrepaidDetailSheet(
  BuildContext context, {
  required double prepaidCapHtg,
  required double itemsSubtotalHtg,
  required bool staffMarkedPaid,
  required bool isDark,
}) {
  final est = estimatedBillTotalHtgFromSubtotal(itemsSubtotalHtg);
  final headroom = prepaidHeadroomHtgFromSubtotal(
    prepaidCapHtg: prepaidCapHtg,
    itemsSubtotalHtg: itemsSubtotalHtg,
  );
  final isOver = headroom <= 0.009;
  final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
  final onSurface = isDark ? AppColors.warmWhite : AppColors.nearBlack;
  final surface = isDark ? AppColors.darkSurface : AppColors.white;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.savings_outlined,
                    size: 18, color: AppColors.deepGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Montant prépayé',
                  style: AppTextStyles.h3(color: onSurface),
                ),
              ),
              AppCloseButton(onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.deepGreen.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Text('Montant prépayé',
                    style: AppTextStyles.caption(color: muted)),
                const Spacer(),
                Text(
                  CurrencyFormatter.local(ctx, prepaidCapHtg),
                  style: AppTextStyles.body(color: AppColors.deepGreen)
                      .copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Note estimée (sous-total + 10 % service + 10 % taxe)',
            value: CurrencyFormatter.local(ctx, est),
            labelColor: muted,
            valueColor: onSurface,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: isOver ? 'Remaining under prepaid' : 'Disponible à dépenser',
            value: CurrencyFormatter.local(ctx, headroom),
            labelColor: muted,
            valueColor: isOver ? AppColors.boldRed : AppColors.deepGreen,
            valueBold: true,
          ),
          if (staffMarkedPaid) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.amber),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Marqué payé — le client peut encore ajouter des articles jusqu\'à la fermeture de la visite.',
                      style: AppTextStyles.caption(color: AppColors.amber)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ── Compact tappable chip for order headers ───────────────────────────────────

/// Small pill-shaped chip in the order-detail header.
/// Tapping opens [showPrepaidDetailSheet].
/// Color: amber when payment not yet confirmed, green when confirmed.
class OrderPrepaidHeaderBanner extends StatelessWidget {
  final double prepaidCapHtg;
  final double itemsSubtotalHtg;
  final bool staffMarkedPaid;
  final bool isDark;

  const OrderPrepaidHeaderBanner({
    super.key,
    required this.prepaidCapHtg,
    required this.itemsSubtotalHtg,
    required this.staffMarkedPaid,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final headroom = prepaidHeadroomHtgFromSubtotal(
      prepaidCapHtg: prepaidCapHtg,
      itemsSubtotalHtg: itemsSubtotalHtg,
    );
    final isOver = headroom <= 0.009;
    final chipColor = isOver
        ? AppColors.boldRed
        : staffMarkedPaid
            ? AppColors.deepGreen
            : AppColors.amber;

    return GestureDetector(
      onTap: () => showPrepaidDetailSheet(
        context,
        prepaidCapHtg: prepaidCapHtg,
        itemsSubtotalHtg: itemsSubtotalHtg,
        staffMarkedPaid: staffMarkedPaid,
        isDark: isDark,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: 13, color: chipColor),
            const SizedBox(width: 5),
            Text(
              'Prepaid ${CurrencyFormatter.local(context, prepaidCapHtg)}',
              style: AppTextStyles.caption(color: chipColor)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            if (!isOver) ...[
              const SizedBox(width: 4),
              Text(
                '· ${CurrencyFormatter.local(context, headroom)} left',
                style: AppTextStyles.caption(
                        color: chipColor.withValues(alpha: 0.8))
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Text(
                '· À la limite',
                style: AppTextStyles.caption(color: chipColor)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(width: 5),
            Icon(Icons.info_outline,
                size: 12, color: chipColor.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final bool valueBold;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: AppTextStyles.caption(color: labelColor))),
        const SizedBox(width: 8),
        Text(
          value,
          style: AppTextStyles.body(color: valueColor).copyWith(
            fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

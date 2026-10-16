import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../providers/app_notification_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import '../utils/order_bill_estimate.dart';
import 'apply_store_credit_sheet.dart';
import 'discount_approval_dialog.dart';

/// After staff confirms payment on a prepaid table visit, use this flow to
/// close the order and optionally handle unused prepaid balance (credit / refund).
Future<void> showPrepaidCompleteOrderDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool isDark,
  required String orderLabel,
  required int orderId,
  required double prepaidCapHtg,
  required double itemsSubtotalHtg,
  required Future<void> Function() markVisitCompleted,
}) async {
  final est = estimatedBillTotalHtgFromSubtotal(itemsSubtotalHtg);
  final balanceLeft = prepaidHeadroomHtgFromSubtotal(
    prepaidCapHtg: prepaidCapHtg,
    itemsSubtotalHtg: itemsSubtotalHtg,
  );
  final hasUnused = balanceLeft > 0.009;

  final bg = isDark ? AppColors.darkSurface : AppColors.white;
  final onSurface = isDark ? AppColors.warmWhite : AppColors.nearBlack;
  final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
  final accent = hasUnused ? AppColors.amber : AppColors.deepGreen;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black45,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.event_available_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Complete prepaid order',
                              style: AppTextStyles.h3(color: onSurface)
                                  .copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              orderLabel,
                              style: AppTextStyles.caption(color: muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 20),
                        color: muted,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBackground.withValues(alpha: 0.6)
                          : const Color(0xFFF4F6F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFE4E7EC),
                      ),
                    ),
                    child: Column(
                      children: [
                        _SummaryLine(
                          label: 'Prepaid amount',
                          value: CurrencyFormatter.local(ctx, prepaidCapHtg),
                          valueColor: AppColors.deepGreen,
                          muted: muted,
                          onSurface: onSurface,
                        ),
                        const SizedBox(height: 10),
                        _SummaryLine(
                          label: 'Est. bill (incl. tax & service)',
                          value: CurrencyFormatter.local(ctx, est),
                          valueColor: onSurface,
                          muted: muted,
                          onSurface: onSurface,
                        ),
                        if (hasUnused) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          _SummaryLine(
                            label: 'Unused balance',
                            value: CurrencyFormatter.local(ctx, balanceLeft),
                            valueColor: AppColors.amber,
                            muted: muted,
                            onSurface: onSurface,
                            emphasize: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasUnused) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Choose how to handle the unused amount, or close the order if you will settle it outside the app.',
                      style: AppTextStyles.caption(color: muted).copyWith(
                        height: 1.35,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'The bill is fully covered by the prepaid amount. You can close this order.',
                      style: AppTextStyles.caption(color: muted).copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (!hasUnused) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await markVisitCompleted();
                          if (!context.mounted) return;
                          ref.read(appNotificationProvider.notifier).show(
                                'Prepaid order completed.',
                              );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepGreen,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Complete Order',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final customerId = await pickCustomerForStoreCreditIssue(
                            context,
                            ref,
                            isDark: isDark,
                          );
                          if (customerId == null || !context.mounted) return;
                          ref.read(customerProvider.notifier).issueStoreCredit(
                                customerId: customerId,
                                amountHtg: balanceLeft,
                                description:
                                    'Unused prepaid balance — $orderLabel',
                                orderId: '$orderId',
                              );
                          await markVisitCompleted();
                          if (!context.mounted) return;
                          ref.read(appNotificationProvider.notifier).show(
                                'Store credit issued — order completed.',
                              );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepGreen,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.savings_outlined, size: 20),
                        label: const Text(
                          'Issue store credit',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await showAdminApprovalDialog(
                            context,
                            ref,
                            message:
                                'Confirm the unused balance of '
                                '${CurrencyFormatter.local(context, balanceLeft)} '
                                'was refunded to the guest (cash, card reversal, etc.).',
                            isDark: isDark,
                            title: 'Record refund',
                          );
                          if (ok != true || !context.mounted) return;
                          await markVisitCompleted();
                          if (!context.mounted) return;
                          ref.read(appNotificationProvider.notifier).show(
                                'Refund recorded — order completed.',
                              );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.amber,
                          side: BorderSide(
                            color: AppColors.amber.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.currency_exchange_rounded,
                            size: 20),
                        label: const Text(
                          'Record refund',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await showAdminApprovalDialog(
                            context,
                            ref,
                            message:
                                'Complete this order without recording store '
                                'credit or a refund? Unused balance: '
                                '${CurrencyFormatter.local(context, balanceLeft)}.',
                            isDark: isDark,
                            title: 'Complete without credit or refund',
                          );
                          if (ok != true || !context.mounted) return;
                          await markVisitCompleted();
                          if (!context.mounted) return;
                          ref.read(appNotificationProvider.notifier).show(
                                'Order completed — settle unused balance separately if needed.',
                                kind: AppNotificationKind.warning,
                              );
                        },
                        child: Text(
                          'Complete without credit or refund',
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue,
                          ).copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color muted;
  final Color onSurface;
  final bool emphasize;

  const _SummaryLine({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.muted,
    required this.onSurface,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.caption(color: muted)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.body(color: valueColor).copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              fontSize: emphasize ? 14 : 13,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import '../utils/order_bill_estimate.dart';

/// Shown when add-on items would push the estimated bill over the prepaid cap.
/// Clean, compact, prominent — one main message + a brief note.
Future<void> showPrepaidAddBlockedDialog(
  BuildContext context, {
  required bool isDark,
  required double prepaidCapHtg,
  required double itemsSubtotalHtg,
}) async {
  final headroom = prepaidHeadroomHtgFromSubtotal(
    prepaidCapHtg: prepaidCapHtg,
    itemsSubtotalHtg: itemsSubtotalHtg,
  );
  final bg = isDark ? AppColors.darkSurface : AppColors.white;
  final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top accent stripe
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.savings_outlined,
                        size: 22, color: AppColors.amber),
                  ),
                  const SizedBox(height: 14),
                  // Main message — prominent
                  Text(
                    'Solde prépayé : ${CurrencyFormatter.local(ctx, headroom)} disponible',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h3(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ).copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'of ${CurrencyFormatter.local(ctx, prepaidCapHtg)} prepaid',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: muted)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  // Divider
                  Divider(
                      height: 1,
                      color: (isDark ? AppColors.darkBorder
                          : const Color(0xFFE8E8E8))),
                  const SizedBox(height: 12),
                  // Note
                  Text(
                    'Ces articles dépassent le montant prépayé (service et taxe inclus). Retirez des articles ou ajustez le prépaiement.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(color: muted),
                  ),
                  const SizedBox(height: 18),
                  // Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFF0F0F0),
                        foregroundColor:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: const Text('Compris',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

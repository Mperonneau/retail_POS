import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Shown when a user tries to mark a takeout/delivery order as "Terminé"
/// while payment has not been made (neither at counter nor via payment link).
///
/// Returns `true` if the user wants to open the payment / bill screen,
/// `null` if dismissed.
class UnpaidCompletionDialog extends StatelessWidget {
  final String orderLabel;
  final bool isDark;

  const UnpaidCompletionDialog({
    super.key,
    required this.orderLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final warnColor = AppColors.amber;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: warnColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.warning_amber_rounded,
                size: 22, color: warnColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Paiement incomplet',
              style: AppTextStyles.h3(color: textPrimary),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Le paiement de $orderLabel n\'est pas encore terminé. '
            'Encaissez avant de marquer la commande comme terminée.',
            style: AppTextStyles.body(color: textSecondary)
                .copyWith(height: 1.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Annuler',
            style: AppTextStyles.button(color: textSecondary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.request_quote_outlined, size: 16),
          label: const Text('Ouvrir le paiement'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
            foregroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }
}

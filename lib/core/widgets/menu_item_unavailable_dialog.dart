import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/menu_item_availability.dart';

/// Modal (dialog) when a menu item cannot be added — prefer over snackbars for POS clarity.
Future<void> showMenuItemUnavailableDialog(
  BuildContext context, {
  required MenuItemOrderability orderability,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final msg = orderability.staffDialogMessage();

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final inset = MediaQuery.paddingOf(ctx);
      return Dialog(
        insetPadding: EdgeInsets.fromLTRB(
          20,
          inset.top + 16,
          20,
          inset.bottom + 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.boldRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: AppColors.boldRed,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacing16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Out of Stock',
                            style: AppTextStyles.h2(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack,
                            ),
                          ),
                          const SizedBox(height: AppConstants.spacing8),
                          Text(
                            msg,
                            style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacing24,
                        vertical: AppConstants.spacing12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'OK',
                      style: AppTextStyles.button(color: AppColors.nearBlack),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

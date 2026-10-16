import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_button.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.skyBlue.withValues(alpha: 0.1)
                    : AppColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Text(
              title,
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              message,
              style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppConstants.spacing32),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                fullWidth: false,
                width: 200,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

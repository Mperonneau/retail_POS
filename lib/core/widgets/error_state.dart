import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_button.dart';

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor = isDark ? AppColors.coralRed : AppColors.boldRed;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 34, color: errorColor),
            ),
            const SizedBox(height: AppConstants.spacing16),
            Text(
              'Oops!',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              message,
              style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppConstants.spacing24),
              AppButton(
                label: 'Try Again',
                onPressed: onRetry,
                variant: AppButtonVariant.danger,
                icon: Icons.refresh_rounded,
                fullWidth: false,
                width: 160,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

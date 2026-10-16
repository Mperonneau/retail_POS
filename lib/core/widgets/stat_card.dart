import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_card.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final double? percentChange;
  final IconData icon;
  final Color iconColor;
  final Color? iconBackground;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.percentChange,
    required this.icon,
    this.iconColor = AppColors.primaryBlue,
    this.iconBackground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPositive = (percentChange ?? 0) >= 0;
    final changeColor = isPositive
        ? (isDark ? AppColors.mediumGreen : AppColors.deepGreen)
        : (isDark ? AppColors.coralRed : AppColors.boldRed);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppConstants.spacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBackground ??
                      (isDark
                          ? AppColors.skyBlue.withValues(alpha: 0.15)
                          : AppColors.lightBlue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // FittedBox shrinks long currency/number values (e.g. "47 540,00 HTG")
          // when the grid cell is narrow, preventing horizontal ellipsis-ing
          // and keeping vertical height predictable.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.statNumber(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (subtitle != null || percentChange != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (subtitle != null)
                  Expanded(
                    child: Text(
                      subtitle!,
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (percentChange != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 10,
                          color: changeColor,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${percentChange!.abs().toStringAsFixed(1)}%',
                          style: AppTextStyles.caption(color: changeColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

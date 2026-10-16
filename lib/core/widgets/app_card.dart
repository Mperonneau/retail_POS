import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/constants.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool elevated;
  /// Optional left accent (e.g. order status) — matches card corner radius.
  final Color? accentBorderColor;
  final double accentBorderWidth;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.borderRadius = AppConstants.radiusCard,
    this.elevated = true,
    this.accentBorderColor,
    this.accentBorderWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = color ?? (isDark ? AppColors.darkSurface : AppColors.white);
    final shadows = elevated
        ? (isDark ? AppColors.cardShadowDark : AppColors.cardShadow)
        : <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
        border: accentBorderColor != null
            ? Border(
                left: BorderSide(
                  color: accentBorderColor!,
                  width: accentBorderWidth,
                ),
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppConstants.spacing16),
            child: child,
          ),
        ),
      ),
    );
  }
}

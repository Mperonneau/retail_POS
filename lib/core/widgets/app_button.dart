import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

enum AppButtonVariant { primary, secondary, danger, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;
  final double? width;
  /// Tighter height and vertical padding (e.g. housekeeping card actions).
  final bool compact;
  /// Even shorter than [compact] (e.g. [BillActionBar] payment row).
  final bool dense;
  /// 1px solid outline (e.g. bottom-sheet grids where filled/ghost buttons need a visible edge).
  final bool solidBorder;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.width,
    this.compact = false,
    this.dense = false,
    this.solidBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = fullWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : width;
        return SizedBox(
          width: w,
          height: dense
              ? AppConstants.buttonHeightDense
              : (compact
                  ? AppConstants.buttonHeightCompact
                  : AppConstants.buttonHeight),
          child: _buildButton(isDark),
        );
      },
    );
  }

  static final EdgeInsets _compactPadding =
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
  static final EdgeInsets _densePadding =
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4);

  Widget _buildButton(bool isDark) {
    final pad = dense ? _densePadding : (compact ? _compactPadding : null);
    final minSize = (compact || dense) ? Size.zero : null;
    final tap = (compact || dense) ? MaterialTapTargetSize.shrinkWrap : null;

    final primaryBorder = BorderSide(
      color: AppColors.nearBlack.withValues(alpha: 0.35),
      width: 1,
    );
    final ghostBorder = BorderSide(
      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
      width: 1,
    );
    final dangerBorder = BorderSide(
      color: AppColors.white.withValues(alpha: 0.45),
      width: 1,
    );

    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: AppColors.nearBlack,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton)),
            side: solidBorder ? primaryBorder : null,
            elevation: 0,
            padding: pad,
            minimumSize: minSize,
            tapTargetSize: tap,
          ),
          child: _buildContent(AppColors.nearBlack),
        );
      case AppButtonVariant.secondary:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
            side: BorderSide(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton)),
            padding: pad,
            minimumSize: minSize,
            tapTargetSize: tap,
          ),
          child: _buildContent(isDark ? AppColors.skyBlue : AppColors.primaryBlue),
        );
      case AppButtonVariant.danger:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? AppColors.coralRed : AppColors.boldRed,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton)),
            side: solidBorder ? dangerBorder : null,
            elevation: 0,
            padding: pad,
            minimumSize: minSize,
            tapTargetSize: tap,
          ),
          child: _buildContent(AppColors.white),
        );
      case AppButtonVariant.ghost:
        return TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton)),
            side: solidBorder ? ghostBorder : null,
            padding: pad,
            minimumSize: minSize,
            tapTargetSize: tap,
          ),
          child: _buildContent(isDark ? AppColors.skyBlue : AppColors.primaryBlue),
        );
    }
  }

  Widget _buildContent(Color textColor) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(textColor),
        ),
      );
    }
    if (icon != null) {
      final iconSize = dense ? 15.0 : 18.0;
      final gap = dense ? 6.0 : 8.0;
      final textStyle = dense
          ? AppTextStyles.button(color: textColor).copyWith(fontSize: 12)
          : AppTextStyles.button(color: textColor);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: textColor),
          SizedBox(width: gap),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: textStyle,
                maxLines: 1,
              ),
            ),
          ),
        ],
      );
    }
    final textStyle = dense
        ? AppTextStyles.button(color: textColor).copyWith(fontSize: 12)
        : AppTextStyles.button(color: textColor);
    return Text(label, style: textStyle);
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Round close button used by panels, sheets and dialogs.
class AppCloseButton extends StatelessWidget {
  const AppCloseButton({
    super.key,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 20,
    this.tooltip = 'Fermer',
  });

  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    final fill = isDark ? AppColors.darkSurface : AppColors.white;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isDark ? Border.all(color: AppColors.darkBorder) : null,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: iconSize,
                    color: enabled ? ink : ink.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

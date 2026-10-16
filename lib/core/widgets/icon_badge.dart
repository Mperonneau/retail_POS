import 'package:flutter/material.dart';

/// Standard sizes for icon badges used throughout the app.
/// sm — stat cards (32 × 32, 16 px icon)
/// md — list rows, order cards, dashboard widgets (40 × 40, 20 px icon)
/// lg — menu / product cards (48 × 48, 24 px icon)
enum IconBadgeSize { sm, md, lg }

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final IconBadgeSize size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.size = IconBadgeSize.md,
  });

  @override
  Widget build(BuildContext context) {
    final (double box, double iconSize) = switch (size) {
      IconBadgeSize.sm => (32.0, 16.0),
      IconBadgeSize.md => (40.0, 20.0),
      IconBadgeSize.lg => (48.0, 24.0),
    };

    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

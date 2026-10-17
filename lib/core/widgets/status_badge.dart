import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

enum StatusType {
  available,
  occupied,
  billRequested,
  reserved,
  maintenance,
  cleaning,
  checkoutToday,
  pending,
  inProgress,
  done,
  lowStock,
  outOfStock,
  active,
  inactive,
}

/// Accent color for [StatusType] — matches [StatusBadge] (e.g. order card left border).
Color statusTypeAccentColor(StatusType type, {required bool isDark}) {
  return _statusConfigForType(type, isDark).color;
}

_StatusConfig _statusConfigForType(StatusType type, bool isDark) {
  switch (type) {
    case StatusType.available:
      return _StatusConfig(isDark ? AppColors.mediumGreen : AppColors.deepGreen, 'Disponible');
    case StatusType.occupied:
      return _StatusConfig(isDark ? AppColors.coralRed : AppColors.boldRed, 'Occupé');
    case StatusType.billRequested:
      return _StatusConfig(AppColors.amber, 'Addition demandée');
    case StatusType.reserved:
      return _StatusConfig(AppColors.statusReserved, 'Réservé');
    case StatusType.maintenance:
      return _StatusConfig(AppColors.statusMaintenance, 'Entretien');
    case StatusType.cleaning:
      return _StatusConfig(AppColors.skyBlue, 'Ménage');
    case StatusType.checkoutToday:
      return _StatusConfig(AppColors.statusCheckoutToday, 'Départ aujourd\'hui');
    case StatusType.pending:
      return _StatusConfig(AppColors.amber, 'En attente');
    case StatusType.inProgress:
      return _StatusConfig(AppColors.skyBlue, 'En cours');
    case StatusType.done:
      return _StatusConfig(isDark ? AppColors.mediumGreen : AppColors.deepGreen, 'Terminé');
    case StatusType.lowStock:
      return _StatusConfig(AppColors.amber, 'Stock bas');
    case StatusType.outOfStock:
      return _StatusConfig(isDark ? AppColors.coralRed : AppColors.boldRed, 'Rupture de stock');
    case StatusType.active:
      return _StatusConfig(isDark ? AppColors.mediumGreen : AppColors.deepGreen, 'Actif');
    case StatusType.inactive:
      return _StatusConfig(isDark ? AppColors.coolGray : AppColors.darkGray, 'Inactif');
  }
}

class StatusBadge extends StatelessWidget {
  final StatusType status;
  final String? customLabel;
  final bool compact;

  /// Smallest variant (dense lists / grid tiles): tighter padding and text.
  final bool micro;

  const StatusBadge({
    super.key,
    required this.status,
    this.customLabel,
    this.compact = false,
    this.micro = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _statusConfigForType(status, isDark);

    final hPad = micro ? 4.0 : (compact ? 6.0 : 10.0);
    final vPad = micro ? 1.0 : (compact ? 2.0 : 4.0);
    final dot = micro ? 4.0 : 6.0;
    final gap = micro ? 3.0 : 4.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: hPad,
        vertical: vPad,
      ),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(micro ? 4 : AppConstants.radiusBadge),
        border: Border.all(color: config.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: config.color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: gap),
          Text(
            customLabel ?? config.label,
            style: micro
                ? AppTextStyles.caption(color: config.color)
                    .copyWith(fontSize: 9, height: 1.1)
                : AppTextStyles.caption(color: config.color),
          ),
        ],
      ),
    );
  }
}

class _StatusConfig {
  final Color color;
  final String label;
  const _StatusConfig(this.color, this.label);
}

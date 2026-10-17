import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/constants.dart';

/// See Bill | Add Items | Merge (optional) | Cancel Order
///
/// Compact icon+label columns shown at the top of order detail drawers.
/// Pass [onMergeTable] (non-null) to show the purple Merge cell — only for dine-in orders.
class OrderDetailQuickActionsBar extends StatelessWidget {
  final bool isDark;
  final Color borderColor;
  final VoidCallback onSeeBill;
  final VoidCallback onAddItems;
  final VoidCallback onCancelOrder;

  /// When false (e.g. order already paid), Add Items is muted and shows [addItemsDisabledMessage] instead.
  final bool canAddItems;
  final String addItemsDisabledMessage;
  /// Shown when Add Items is tapped while disabled (e.g. modal banner). If null, disabled taps do nothing.
  final void Function(String message)? onUserMessage;

  /// When non-null, a purple "Fusionner" cell is added between Add Items and Cancel Order.
  /// Only pass for dine-in orders.
  final VoidCallback? onMergeTable;

  const OrderDetailQuickActionsBar({
    super.key,
    required this.isDark,
    required this.borderColor,
    required this.onSeeBill,
    required this.onAddItems,
    required this.onCancelOrder,
    this.canAddItems = true,
    this.addItemsDisabledMessage =
        'Cette commande est payée. Ouvrez une nouvelle commande pour ajouter des articles.',
    this.onUserMessage,
    this.onMergeTable,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    const mergeColor = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          _QuickActionCell(
            icon: Icons.receipt_long_outlined,
            label: 'Voir la note',
            color: primary,
            onTap: onSeeBill,
          ),
          _QuickActionCell(
            icon: Icons.add_circle_outline,
            label: 'Ajouter des articles',
            color: canAddItems ? primary : AppColors.coolGray,
            onTap: onAddItems,
            enabled: canAddItems,
            disabledHint: addItemsDisabledMessage,
            onUserMessage: onUserMessage,
          ),
          if (onMergeTable != null)
            _QuickActionCell(
              icon: Icons.merge_type_rounded,
              label: 'Fusionner',
              color: mergeColor,
              onTap: onMergeTable!,
            ),
          _QuickActionCell(
            icon: Icons.cancel_outlined,
            label: 'Annuler la commande',
            color: AppColors.error,
            onTap: onCancelOrder,
          ),
        ],
      ),
    );
  }
}

class _QuickActionCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledHint;
  final void Function(String message)? onUserMessage;

  const _QuickActionCell({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.disabledHint,
    this.onUserMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled
            ? onTap
            : () {
                final msg = disabledHint;
                if (msg != null && msg.isNotEmpty) {
                  onUserMessage?.call(msg);
                }
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

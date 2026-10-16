import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

enum KitchenHoldDecision { holdUntilPaid, startNow }

/// Confirmation dialog shown when a takeout/delivery order uses "Send payment
/// link". Asks whether the kitchen should start preparing immediately or wait
/// until payment is confirmed.
class KitchenHoldDialog extends StatefulWidget {
  final bool isDark;
  final String orderLabel;

  const KitchenHoldDialog({
    super.key,
    required this.isDark,
    required this.orderLabel,
  });

  @override
  State<KitchenHoldDialog> createState() => _KitchenHoldDialogState();
}

class _KitchenHoldDialogState extends State<KitchenHoldDialog> {
  KitchenHoldDecision _decision = KitchenHoldDecision.holdUntilPaid;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.soup_kitchen_outlined,
                size: 20, color: AppColors.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kitchen Preparation',
                    style: AppTextStyles.h3(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack)),
                Text(widget.orderLabel,
                    style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'A payment link will be sent to the customer. '
              'Should the kitchen start preparing this order now or '
              'wait until payment is confirmed?',
              style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(height: 16),
            _OptionTile(
              icon: Icons.pause_circle_outline_rounded,
              title: 'Hold until paid',
              subtitle:
                  'Kitchen will not receive the order until payment is confirmed.',
              selected: _decision == KitchenHoldDecision.holdUntilPaid,
              isDark: isDark,
              accent: accent,
              onTap: () =>
                  setState(() => _decision = KitchenHoldDecision.holdUntilPaid),
            ),
            const SizedBox(height: 8),
            _OptionTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'Start preparing now',
              subtitle:
                  'Kitchen will begin immediately — payment can arrive later.',
              selected: _decision == KitchenHoldDecision.startNow,
              isDark: isDark,
              accent: accent,
              onTap: () =>
                  setState(() => _decision = KitchenHoldDecision.startNow),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: AppTextStyles.button(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, _decision),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Confirm & Send'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.deepGreen,
            foregroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusButton)),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.12 : 0.06)
              : (isDark
                  ? AppColors.darkBackground
                  : const Color(0xFFF7F7F7)),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard - 2),
          border: Border.all(
            color: selected
                ? accent
                : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 24,
                color: selected
                    ? accent
                    : (isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.body(
                        color: selected
                            ? accent
                            : (isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack),
                      ).copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTextStyles.caption(
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray,
                      )),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 20, color: accent),
          ],
        ),
      ),
    );
  }
}

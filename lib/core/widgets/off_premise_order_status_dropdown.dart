import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

/// Flow for takeout / delivery: Pending → In progress → Ready → Completed (stored as `complete`).
const List<String> kOffPremiseFlowStatuses = [
  'pending',
  'in_progress',
  'ready',
  'complete',
];

String normalizeOffPremiseStatus(String? raw) {
  if (raw == null || raw.isEmpty) return 'pending';
  final s = raw == 'preparing' ? 'in_progress' : raw;
  if (kOffPremiseFlowStatuses.contains(s)) return s;
  if (s == 'delivered' || s == 'charged' || s == 'complete') return 'complete';
  return 'pending';
}

String offPremiseStatusLabel(String status) {
  switch (normalizeOffPremiseStatus(status)) {
    case 'pending':
      return 'Pending';
    case 'in_progress':
      return 'In progress';
    case 'ready':
      return 'Ready';
    case 'complete':
      return 'Completed';
    default:
      return status;
  }
}

/// Shorter labels so payment + order status fit on one row on cards.
String _offPremiseStatusLabelCompact(String status) {
  switch (normalizeOffPremiseStatus(status)) {
    case 'pending':
      return 'Pending';
    case 'in_progress':
      return 'In prog.';
    case 'ready':
      return 'Ready';
    case 'complete':
      return 'Done';
    default:
      return offPremiseStatusLabel(status);
  }
}

StatusType offPremiseStatusType(String status) {
  switch (normalizeOffPremiseStatus(status)) {
    case 'pending':
      return StatusType.pending;
    case 'in_progress':
      return StatusType.inProgress;
    case 'ready':
      return StatusType.done;
    case 'complete':
      return StatusType.active;
    default:
      return StatusType.inactive;
  }
}

/// PAID / NOT PAID chip for takeout & delivery (placed left of [OffPremiseOrderStatusDropdown]).
class OffPremisePaymentStatusBadge extends StatelessWidget {
  final bool isPaid;
  final bool isDark;

  const OffPremisePaymentStatusBadge({
    super.key,
    required this.isPaid,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (isPaid) {
      final color =
          isDark ? AppColors.mediumGreen : AppColors.deepGreen;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          'PAID',
          style: AppTextStyles.caption(color: color).copyWith(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    // NOT PAID — light red background so unpaid stands out on takeout/delivery cards
    final fg = isDark ? AppColors.coralRed : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
        border: Border.all(color: fg.withValues(alpha: 0.42)),
      ),
      child: Text(
        'NOT PAID',
        style: AppTextStyles.caption(color: fg).copyWith(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Same look as [StatusBadge], opens a menu to pick the flow status.
class OffPremiseOrderStatusDropdown extends StatelessWidget {
  final String status;
  final bool isDark;
  final bool compact;
  final ValueChanged<String> onStatusSelected;

  const OffPremiseOrderStatusDropdown({
    super.key,
    required this.status,
    required this.isDark,
    this.compact = false,
    required this.onStatusSelected,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeOffPremiseStatus(status);
    final st = offPremiseStatusType(normalized);
    final config = _badgeConfig(st, isDark);

    return PopupMenuButton<String>(
      tooltip: 'Order status',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      ),
      // Defer so the popup route finishes dismissing; otherwise Navigator.pop
      // from the callback can run while the navigator is still locked (assertion
      // on web: !_debugLocked in Navigator.dispose).
      onSelected: (v) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          onStatusSelected(v);
        });
      },
      itemBuilder: (ctx) => [
        for (final v in kOffPremiseFlowStatuses)
          PopupMenuItem<String>(
            value: v,
            child: Text(offPremiseStatusLabel(v)),
          ),
      ],
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 5 : 10,
                  vertical: compact ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusBadge),
                  border: Border.all(
                    color: config.color.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 5 : 6,
                      height: compact ? 5 : 6,
                      decoration: BoxDecoration(
                        color: config.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: compact ? 3 : 4),
                    Text(
                      compact
                          ? _offPremiseStatusLabelCompact(normalized)
                          : offPremiseStatusLabel(normalized),
                      style: AppTextStyles.caption(color: config.color).copyWith(
                        fontSize: compact ? 8 : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: compact ? 1 : 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: compact ? 16 : 18,
                      color: config.color,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeStyleConfig {
  final Color color;
  const _BadgeStyleConfig(this.color);
}

_BadgeStyleConfig _badgeConfig(StatusType type, bool isDark) {
  switch (type) {
    case StatusType.pending:
      return _BadgeStyleConfig(AppColors.amber);
    case StatusType.inProgress:
      return _BadgeStyleConfig(AppColors.skyBlue);
    case StatusType.done:
      return _BadgeStyleConfig(
          isDark ? AppColors.mediumGreen : AppColors.deepGreen);
    case StatusType.active:
      return _BadgeStyleConfig(
          isDark ? AppColors.mediumGreen : AppColors.deepGreen);
    default:
      return _BadgeStyleConfig(AppColors.coolGray);
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Result returned from [showMergeTableSheet].
class MergeTableResult {
  final int survivorId;
  final int absorbedId;
  const MergeTableResult({required this.survivorId, required this.absorbedId});
}

/// Data needed to describe one candidate table.
class MergeTableOption {
  final int orderId;
  final String tableName;
  final double totalHtg;
  final int itemCount;
  final bool isBlocked;

  const MergeTableOption({
    required this.orderId,
    required this.tableName,
    required this.totalHtg,
    required this.itemCount,
    required this.isBlocked,
  });
}

/// Data for displaying the pre-merge snapshot (absorbed order).
class MergeSnapshotData {
  final int orderId;
  final String tableName;
  final DateTime mergedAt;
  final List<MergeSnapshotItem> items;
  final double totalHtg;
  final String? waiter;
  final String? guestName;

  const MergeSnapshotData({
    required this.orderId,
    required this.tableName,
    required this.mergedAt,
    required this.items,
    required this.totalHtg,
    this.waiter,
    this.guestName,
  });
}

class MergeSnapshotItem {
  final String name;
  final int quantity;
  final double priceHtg;
  const MergeSnapshotItem(
      {required this.name, required this.quantity, required this.priceHtg});
}

/// Shows the merge-table picker bottom sheet.
///
/// [currentOrderId] is the order that will be the **survivor**.
/// [currentTableName] is shown in the UI.
/// [candidates] is the list of OTHER dine-in orders (same module).
///
/// Returns a [MergeTableResult] when the user confirms, or `null` if cancelled.
Future<MergeTableResult?> showMergeTableSheet({
  required BuildContext context,
  required bool isDark,
  required int currentOrderId,
  required String currentTableName,
  required List<MergeTableOption> candidates,
}) {
  return showModalBottomSheet<MergeTableResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MergeTableSheet(
      isDark: isDark,
      currentOrderId: currentOrderId,
      currentTableName: currentTableName,
      candidates: candidates,
    ),
  );
}

/// Shows the warning dialog when a merge is blocked.
Future<void> showMergeBlockedDialog({
  required BuildContext context,
  required bool isDark,
  required String tableName,
  required String reason,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MergeBlockedDialog(
      isDark: isDark,
      tableName: tableName,
      reason: reason,
    ),
  );
}

/// Shows a success dialog after two tables have been merged.
Future<void> showMergeSuccessDialog({
  required BuildContext context,
  required bool isDark,
  required String survivorName,
  required String absorbedName,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MergeSuccessDialog(
      isDark: isDark,
      survivorName: survivorName,
      absorbedName: absorbedName,
    ),
  );
}

/// Shows a modal with the snapshot of the absorbed order.
Future<void> showMergeSnapshotModal({
  required BuildContext context,
  required bool isDark,
  required MergeSnapshotData snapshot,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MergeSnapshotDialog(
      isDark: isDark,
      snapshot: snapshot,
    ),
  );
}

// ── Merge badge (on order card) ───────────────────────────────────────────────

/// Small tappable chip displayed on merged order cards.
class MergeOrderBadge extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const MergeOrderBadge({super.key, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.merge_type_rounded, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              'Fusionné',
              style: AppTextStyles.caption(color: color).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Merge action cell (in OrderDetailQuickActionsBar) ─────────────────────────

/// Small icon + label column for the "Fusionner" action in the quick actions bar.
/// Matches the style of [_QuickActionCell] in order_detail_quick_actions_bar.dart.
class MergeQuickAction extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const MergeQuickAction({
    super.key,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7C3AED);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.merge_type_rounded, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              'Fusionner',
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

// ── _MergeTableSheet ──────────────────────────────────────────────────────────

class _MergeTableSheet extends StatefulWidget {
  final bool isDark;
  final int currentOrderId;
  final String currentTableName;
  final List<MergeTableOption> candidates;

  const _MergeTableSheet({
    required this.isDark,
    required this.currentOrderId,
    required this.currentTableName,
    required this.candidates,
  });

  @override
  State<_MergeTableSheet> createState() => _MergeTableSheetState();
}

class _MergeTableSheetState extends State<_MergeTableSheet> {
  MergeTableOption? _selected;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE8E8F0);
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    const mergeColor = Color(0xFF7C3AED);
    final maxH = MediaQuery.of(context).size.height * 0.88;

    final availables = widget.candidates.where((c) => !c.isBlocked).toList();
    final blocked = widget.candidates.where((c) => c.isBlocked).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: mergeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.merge_type_rounded,
                      size: 16, color: mergeColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fusionner la table',
                        style: AppTextStyles.h3(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontSize: 15),
                      ),
                      Text(
                        'Table conservée : ${widget.currentTableName}',
                        style:
                            AppTextStyles.caption(color: muted).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: muted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: border),

          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Instruction
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mergeColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: mergeColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 15, color: mergeColor.withValues(alpha: 0.8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Choisissez une table à fusionner avec ${widget.currentTableName}. '
                            'Les articles de la table choisie seront ajoutés à cette commande. '
                            'La table fusionnée sera retirée de la liste active.',
                            style: AppTextStyles.caption(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack)
                                .copyWith(fontSize: 11.5, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (widget.candidates.isEmpty) ...[
                    _EmptyState(isDark: isDark),
                  ] else ...[
                    // Available tables
                    if (availables.isNotEmpty) ...[
                      Text(
                        'CHOISIR LA TABLE À ABSORBER',
                        style: AppTextStyles.caption(color: muted).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...availables.map((opt) => _TableOptionTile(
                            option: opt,
                            isDark: isDark,
                            isSelected: _selected?.orderId == opt.orderId,
                            onTap: () =>
                                setState(() => _selected = opt),
                          )),
                    ],

                    // Blocked tables
                    if (blocked.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'INDISPONIBLE (PAIEMENT EN ATTENTE OU PRÉPAYÉ)',
                        style: AppTextStyles.caption(
                                color: AppColors.warning.withValues(alpha: 0.8))
                            .copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...blocked.map((opt) => _TableOptionTile(
                            option: opt,
                            isDark: isDark,
                            isSelected: false,
                            onTap: null,
                          )),
                    ],
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: bg,
              border: Border(top: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side:
                          BorderSide(color: border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              MergeTableResult(
                                survivorId: widget.currentOrderId,
                                absorbedId: _selected!.orderId,
                              ),
                            ),
                    icon: const Icon(Icons.merge_type_rounded, size: 16),
                    label: Text(
                      _selected == null
                          ? 'Choisir une table'
                          : 'Fusionner ${_selected!.tableName} → ${widget.currentTableName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _selected == null ? muted.withValues(alpha: 0.2) : mergeColor,
                      foregroundColor: _selected == null ? muted : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TableOptionTile ──────────────────────────────────────────────────────────

class _TableOptionTile extends StatelessWidget {
  final MergeTableOption option;
  final bool isDark;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TableOptionTile({
    required this.option,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const mergeColor = Color(0xFF7C3AED);
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE8E8F0);
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final bg = isDark ? AppColors.darkBackground : const Color(0xFFF8F8FC);
    final blockedColor = AppColors.warning;

    final isBlocked = option.isBlocked;
    final activeColor = isSelected ? mergeColor : (isBlocked ? blockedColor : null);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? mergeColor.withValues(alpha: 0.06)
              : (isBlocked ? blockedColor.withValues(alpha: 0.04) : bg),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? mergeColor.withValues(alpha: 0.5)
                : (isBlocked
                    ? blockedColor.withValues(alpha: 0.3)
                    : border),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? mergeColor
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? mergeColor
                      : (isBlocked ? blockedColor : border),
                  width: isSelected ? 0 : 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        option.tableName,
                        style: AppTextStyles.body(
                          color: activeColor ??
                              (isDark ? AppColors.warmWhite : AppColors.nearBlack),
                        ).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (isBlocked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: blockedColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Bloqué',
                            style: AppTextStyles.caption(color: blockedColor)
                                .copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${option.itemCount} article${option.itemCount != 1 ? 's' : ''} · ${CurrencyFormatter.local(context, option.totalHtg)}',
                    style: AppTextStyles.caption(color: muted)
                        .copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),

            if (isBlocked)
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: blockedColor.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.table_restaurant_outlined,
              size: 40, color: muted.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            'Aucune autre table en salle à fusionner.',
            style: AppTextStyles.body(color: muted).copyWith(fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── _MergeSuccessDialog ───────────────────────────────────────────────────────

class _MergeSuccessDialog extends StatelessWidget {
  final bool isDark;
  final String survivorName;
  final String absorbedName;

  const _MergeSuccessDialog({
    required this.isDark,
    required this.survivorName,
    required this.absorbedName,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    const mergeColor = Color(0xFF7C3AED);
    final screenW = MediaQuery.sizeOf(context).width;
    final contentW = (screenW - 48).clamp(260.0, 340.0);

    return AlertDialog(
      backgroundColor: bg,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                size: 18, color: AppColors.deepGreen),
          ),
          const SizedBox(width: 10),
          const Text('Tables fusionnées'),
        ],
      ),
      content: SizedBox(
        width: contentW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Merge visual
            Row(
              children: [
                _TablePill(label: absorbedName, color: muted),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.deepGreen),
                const SizedBox(width: 8),
                _TablePill(label: survivorName, color: mergeColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tous les articles de $absorbedName ont été transférés vers $survivorName. '
              '$absorbedName est de nouveau libre.',
              style: AppTextStyles.body(color: muted)
                  .copyWith(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: mergeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            child: const Text('Compris',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _TablePill extends StatelessWidget {
  final String label;
  final Color color;
  const _TablePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_restaurant_outlined, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.caption(color: color).copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _MergeBlockedDialog ───────────────────────────────────────────────────────

class _MergeBlockedDialog extends StatelessWidget {
  final bool isDark;
  final String tableName;
  final String reason;

  const _MergeBlockedDialog({
    required this.isDark,
    required this.tableName,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    const warningColor = AppColors.warning;
    final screenW = MediaQuery.sizeOf(context).width;
    final contentW = (screenW - 48).clamp(260.0, 340.0);

    return AlertDialog(
      backgroundColor: bg,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: warningColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded,
                size: 18, color: warningColor),
          ),
          const SizedBox(width: 10),
          const Text('Fusion bloquée'),
        ],
      ),
      content: SizedBox(
        width: contentW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Impossible de fusionner $tableName',
              style: AppTextStyles.body(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(reason, style: AppTextStyles.body(color: muted)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// ── _MergeSnapshotDialog ──────────────────────────────────────────────────────

class _MergeSnapshotDialog extends StatelessWidget {
  final bool isDark;
  final MergeSnapshotData snapshot;

  const _MergeSnapshotDialog(
      {required this.isDark, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE8E8F0);
    const mergeColor = Color(0xFF7C3AED);
    final screenW = MediaQuery.sizeOf(context).width;
    final contentW = (screenW - 48).clamp(280.0, 400.0);
    final dateStr = DateFormat('MMM d, yyyy · HH:mm').format(snapshot.mergedAt);

    return AlertDialog(
      backgroundColor: bg,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: mergeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.merge_type_rounded,
                size: 16, color: mergeColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Merged: ${snapshot.tableName}',
                  style: AppTextStyles.h3(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack)
                      .copyWith(fontSize: 15),
                ),
                Text(
                  dateStr,
                  style: AppTextStyles.caption(color: muted)
                      .copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: contentW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Meta row
            if (snapshot.guestName != null || snapshot.waiter != null) ...[
              Row(
                children: [
                  if (snapshot.guestName != null) ...[
                    Icon(Icons.person_outline, size: 13, color: muted),
                    const SizedBox(width: 4),
                    Text(snapshot.guestName!,
                        style: AppTextStyles.caption(color: muted)
                            .copyWith(fontSize: 11)),
                    const SizedBox(width: 12),
                  ],
                  if (snapshot.waiter != null) ...[
                    Icon(Icons.badge_outlined, size: 13, color: muted),
                    const SizedBox(width: 4),
                    Text(snapshot.waiter!,
                        style: AppTextStyles.caption(color: muted)
                            .copyWith(fontSize: 11)),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Items list
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    color: mergeColor.withValues(alpha: 0.06),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Article',
                              style: AppTextStyles.caption(color: muted)
                                  .copyWith(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700)),
                        ),
                        Text('Qté',
                            style: AppTextStyles.caption(color: muted)
                                .copyWith(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 64,
                          child: Text('Montant',
                              style: AppTextStyles.caption(color: muted)
                                  .copyWith(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700),
                              textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: border),

                  // Items
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: snapshot.items.map((item) {
                          final lineTotal = item.priceHtg * item.quantity;
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.warmWhite
                                              : AppColors.nearBlack,
                                        ).copyWith(fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      '×${item.quantity}',
                                      style: AppTextStyles.caption(color: muted)
                                          .copyWith(fontSize: 11),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 64,
                                      child: Text(
                                        CurrencyFormatter.local(
                                            context, lineTotal),
                                        style: AppTextStyles.price()
                                            .copyWith(fontSize: 12),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(height: 1, color: border),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Total row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    color: mergeColor.withValues(alpha: 0.04),
                    child: Row(
                      children: [
                        Text(
                          'Total (${snapshot.tableName})',
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack,
                          ).copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          CurrencyFormatter.local(context, snapshot.totalHtg),
                          style: AppTextStyles.price().copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: mergeColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Terminé'),
        ),
      ],
    );
  }
}

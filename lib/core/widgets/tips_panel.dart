import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tip_management.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/input_formatters.dart';
import '../utils/currency_formatter.dart';
import 'tips_history_panel.dart';
import 'app_close_button.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

void showTipsPanel(BuildContext context, bool isDark) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      pageBuilder: (_, __, ___) => TipsPanel(isDark: isDark),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

// ─── Panel ────────────────────────────────────────────────────────────────────

class TipsPanel extends ConsumerStatefulWidget {
  final bool isDark;
  const TipsPanel({super.key, required this.isDark});

  @override
  ConsumerState<TipsPanel> createState() => _TipsPanelState();
}

class _TipsPanelState extends ConsumerState<TipsPanel> {
  final Map<String, bool> _expanded = {};

  void _showAdjustDialog(
      BuildContext context, String waiter, bool isDark) {
    showDialog<void>(
      context: context,
      builder: (_) => _AdjustDialog(
        waiter: waiter,
        isDark: isDark,
        onSave: (htg, usd, isSub, reason) {
          ref.read(tipProvider.notifier).addAdjustment(
                waiterName: waiter,
                amountHtg: htg,
                amountUsd: usd,
                isSubtraction: isSub,
                reason: reason,
              );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tipState = ref.watch(tipProvider);
    final isDark = widget.isDark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    final panelWidth =
        isWide ? (screenWidth * 0.62).clamp(400.0, 580.0) : screenWidth;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;

    final waiters = tipState.waiterNames;
    final totalHtg = tipState.totalOutstandingHtg;
    final totalUsd = tipState.totalOutstandingUsd;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: isWide ? Alignment.centerRight : Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              color: bg,
              elevation: 16,
              shadowColor: Colors.black26,
              child: SafeArea(
                child: Column(
                  children: [
                    // ── Header ───────────────────────────────────────────
                    _PanelHeader(
                      isDark: isDark,
                      onHistory: () => showTipsHistoryPanel(context, isDark),
                    ),

                    // ── Total outstanding banner ──────────────────────────
                    if (totalHtg > 0)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusCard),
                          border: Border.all(
                              color: AppColors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.payments_outlined,
                                color: AppColors.amber, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Pourboires impayés',
                                style: AppTextStyles.caption(
                                    color: AppColors.amber),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyFormatter.local(context, totalHtg),
                                  style: AppTextStyles.body(
                                          color: AppColors.amber)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '\$${totalUsd.toStringAsFixed(2)}',
                                  style: AppTextStyles.caption(
                                      color: AppColors.amber
                                          .withValues(alpha: 0.75)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // ── Waiter list ───────────────────────────────────────
                    Expanded(
                      child: waiters.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.payments_outlined,
                                        size: 44,
                                        color: isDark
                                            ? AppColors.coolGray
                                            : AppColors.darkGray),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Aucun pourboire pour le moment.',
                                      style: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.coolGray
                                              : AppColors.darkGray),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              children: waiters.map((waiter) {
                                return _WaiterSection(
                                  waiter: waiter,
                                  tipState: tipState,
                                  isDark: isDark,
                                  isExpanded: _expanded[waiter] ?? false,
                                  onToggleExpand: () => setState(() =>
                                      _expanded[waiter] =
                                          !(_expanded[waiter] ?? false)),
                                  onAdjust: () => _showAdjustDialog(
                                      context, waiter, isDark),
                                  onPayOut: () => _confirmPayOut(
                                      context, waiter, tipState, isDark),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPayOut(BuildContext context, String waiter,
      TipState tipState, bool isDark) async {
    final balHtg = tipState.balanceHtgFor(waiter);
    final balUsd = tipState.balanceUsdFor(waiter);
    if (balHtg <= 0 && balUsd <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _PayOutDialog(
        waiter: waiter,
        balHtg: balHtg,
        balUsd: balUsd,
        isDark: isDark,
      ),
    );

    if (confirmed == true) {
      ref
          .read(tipProvider.notifier)
          .payOut(waiterName: waiter, recordedBy: 'Gérant');
    }
  }
}

// ─── Waiter section ───────────────────────────────────────────────────────────

class _WaiterSection extends StatelessWidget {
  final String waiter;
  final TipState tipState;
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onAdjust;
  final VoidCallback onPayOut;

  const _WaiterSection({
    required this.waiter,
    required this.tipState,
    required this.isDark,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onAdjust,
    required this.onPayOut,
  });

  @override
  Widget build(BuildContext context) {
    final balHtg = tipState.balanceHtgFor(waiter);
    final balUsd = tipState.balanceUsdFor(waiter);
    final isPaid = balHtg <= 0 && balUsd <= 0;
    final history = tipState.historyFor(waiter);
    final cardBorder =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final cardBg = isDark ? const Color(0xFF1A2535) : AppColors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: cardBorder),
          boxShadow: isDark ? [] : AppColors.cardShadow,
        ),
        child: Column(
          children: [
            // ── Waiter header row ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        waiter[0].toUpperCase(),
                        style: AppTextStyles.body(color: AppColors.amber)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          waiter,
                          style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.warmWhite
                                      : AppColors.nearBlack)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 1),
                        isPaid
                            ? Row(children: [
                                Icon(Icons.check_circle_outline,
                                    size: 12, color: AppColors.deepGreen),
                                const SizedBox(width: 3),
                                Text('Payé',
                                    style: AppTextStyles.caption(
                                        color: AppColors.deepGreen)),
                              ])
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    CurrencyFormatter.local(context, balHtg),
                                    style: AppTextStyles.body(
                                            color: AppColors.amber)
                                        .copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13),
                                  ),
                                  Text(
                                    '\$${balUsd.toStringAsFixed(2)}',
                                    style: AppTextStyles.caption(
                                        color: AppColors.amber
                                            .withValues(alpha: 0.75)),
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                  // Action buttons
                  if (!isPaid)
                    _ActionButton(
                      label: 'Verser',
                      icon: Icons.payments_outlined,
                      color: AppColors.deepGreen,
                      isDark: isDark,
                      onTap: onPayOut,
                    ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    label: 'Ajuster',
                    icon: Icons.tune_outlined,
                    color: AppColors.amber,
                    isDark: isDark,
                    onTap: onAdjust,
                  ),
                  const SizedBox(width: 4),
                  // History toggle
                  GestureDetector(
                    onTap: onToggleExpand,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${history.length}',
                            style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.skyBlue
                                    : AppColors.primaryBlue),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Transaction history (collapsible) ─────────────────────
            if (isExpanded) ...[
              Divider(height: 1, color: cardBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(
                  children: history
                      .map((e) => _TipHistoryRow(entry: e, isDark: isDark))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Pay-out confirmation dialog ──────────────────────────────────────────────

class _PayOutDialog extends StatelessWidget {
  final String waiter;
  final double balHtg;
  final double balUsd;
  final bool isDark;

  const _PayOutDialog({
    required this.waiter,
    required this.balHtg,
    required this.balUsd,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final dialogBg = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final subColor = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.deepGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payments_outlined,
                        color: AppColors.deepGreen, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verser les pourboires',
                            style: AppTextStyles.h2(color: textColor)),
                        Text(waiter,
                            style: AppTextStyles.caption(
                                color: AppColors.deepGreen)),
                      ],
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 20),

              // ── Amount summary ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                  border: Border.all(
                      color: AppColors.deepGreen.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Montant à verser',
                        style: AppTextStyles.caption(color: subColor)),
                    const SizedBox(height: 6),
                    Text(CurrencyFormatter.local(context, balHtg),
                        style: AppTextStyles.h2(color: AppColors.deepGreen)
                            .copyWith(fontSize: 20)),
                    Text('\$${balUsd.toStringAsFixed(2)} USD',
                        style: AppTextStyles.body(color: subColor)
                            .copyWith(fontSize: 13)),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Cela remettra le solde de pourboires de $waiter à zéro.',
                style: AppTextStyles.body(color: subColor)
                    .copyWith(fontSize: 13),
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 16),

              // ── Buttons ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: subColor,
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton)),
                        ),
                        child: const Text('Annuler',
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton)),
                        ),
                        child: const Text('Confirmer le versement',
                            style:
                                TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Adjust dialog (modal) ────────────────────────────────────────────────────

class _AdjustDialog extends StatefulWidget {
  final String waiter;
  final bool isDark;
  final void Function(double htg, double usd, bool isSub, String reason) onSave;

  const _AdjustDialog({
    required this.waiter,
    required this.isDark,
    required this.onSave,
  });

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  bool _isSubtraction = false;
  final _htgCtrl = TextEditingController();
  final _usdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _htgCtrl.dispose();
    _usdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final htg = double.tryParse(_htgCtrl.text) ?? 0;
    final reason = _reasonCtrl.text.trim();
    if (htg <= 0 || reason.isEmpty) return;
    widget.onSave(
      htg,
      double.tryParse(_usdCtrl.text) ?? 0,
      _isSubtraction,
      reason,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final addColor = AppColors.deepGreen;
    final subColor = AppColors.boldRed;
    final activeColor = _isSubtraction ? subColor : addColor;
    final dialogBg = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_outlined,
                        color: AppColors.amber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ajuster les pourboires',
                            style: AppTextStyles.h2(color: textColor)),
                        Text(widget.waiter,
                            style: AppTextStyles.caption(
                                color: AppColors.amber)),
                      ],
                    ),
                  ),
                  // Close button
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 20),

              // ── Add / Subtract toggle ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _ToggleBtn(
                      label: '+ Ajouter',
                      active: !_isSubtraction,
                      color: addColor,
                      isDark: isDark,
                      onTap: () => setState(() => _isSubtraction = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ToggleBtn(
                      label: '− Retirer',
                      active: _isSubtraction,
                      color: subColor,
                      isDark: isDark,
                      onTap: () => setState(() => _isSubtraction = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Amount fields ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _DialogField(
                      controller: _htgCtrl,
                      label: 'Montant HTG *',
                      prefix: 'HTG ',
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: InputFormatters.decimalAmount,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogField(
                      controller: _usdCtrl,
                      label: 'Montant USD',
                      prefix: '\$ ',
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: InputFormatters.decimalAmount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Reason ────────────────────────────────────────────────
              _DialogField(
                controller: _reasonCtrl,
                label: 'Motif *',
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              Text(
                '* Le montant en HTG et le motif sont obligatoires.',
                style: AppTextStyles.caption(color: labelColor)
                    .copyWith(fontSize: 11),
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 16),

              // ── Action buttons ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: labelColor,
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton)),
                        ),
                        child: const Text('Annuler',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton)),
                        ),
                        child: Text(
                          _isSubtraction ? 'Retirer' : 'Ajouter',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tip history row ──────────────────────────────────────────────────────────

class _TipHistoryRow extends StatelessWidget {
  final TipEntry entry;
  final bool isDark;
  const _TipHistoryRow({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isPayout = entry.type == TipEntryType.payout;
    final isAdj = entry.type == TipEntryType.adjustment;
    final isNeg = entry.amountHtg < 0;

    final color = isPayout
        ? AppColors.deepGreen
        : isAdj
            ? (isNeg ? AppColors.boldRed : AppColors.skyBlue)
            : AppColors.amber;
    final sign = isPayout ? '−' : (isAdj && isNeg ? '−' : '+');
    final amtHtg = entry.amountHtg.abs();
    final amtUsd = entry.amountUsd.abs();

    final typeLabel = isPayout
        ? 'Payout'
        : isAdj
            ? 'Adj.'
            : 'Tip';
    final h = entry.timestamp.hour.toString().padLeft(2, '0');
    final m = entry.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                typeLabel,
                style: AppTextStyles.caption(color: color)
                    .copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.reason,
                  style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack)
                      .copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (entry.linkedTable != null) ...[
                      Text(entry.linkedTable!, style: AppTextStyles.caption()),
                      Text(' · ', style: AppTextStyles.caption()),
                    ],
                    Text('$h:$m', style: AppTextStyles.caption()),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${CurrencyFormatter.local(context, amtHtg)}',
                style: AppTextStyles.body(color: color)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              Text(
                '$sign\$${amtUsd.toStringAsFixed(2)}',
                style:
                    AppTextStyles.caption(color: color.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final bool isDark;
  final VoidCallback onHistory;
  const _PanelHeader({required this.isDark, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payments_outlined,
                color: AppColors.amber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pourboires serveuse',
                    style: AppTextStyles.h2(color: textColor)),
                Text('Gérer les pourboires et versements',
                    style: AppTextStyles.caption()),
              ],
            ),
          ),

          // History button
          GestureDetector(
            onTap: onHistory,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.skyBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.skyBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history_rounded,
                      size: 14, color: AppColors.skyBlue),
                  const SizedBox(width: 5),
                  Text(
                    'Historique',
                    style: AppTextStyles.caption(color: AppColors.skyBlue)
                        .copyWith(
                            fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Close
          AppCloseButton(onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? AppColors.coolGray : AppColors.darkGray;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isDark
                  ? AppColors.darkBorder
                  : const Color(0xFFE0E0E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTextStyles.caption(color: fg)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? Colors.white
        : (isDark ? AppColors.coolGray : AppColors.darkGray);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          border: Border.all(
              color: active
                  ? color
                  : (isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFDDDDDD))),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.body(color: fg)
                .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// Text field used inside the Adjust dialog
class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final bool isDark;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _DialogField({
    required this.controller,
    required this.label,
    required this.isDark,
    this.prefix,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final hintColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC);
    final focusBorderColor =
        isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(fontSize: 14, color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: hintColor),
        prefixText: prefix,
        prefixStyle: TextStyle(fontSize: 14, color: hintColor),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: focusBorderColor, width: 1.5),
        ),
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1E2E42)
            : const Color(0xFFFAFAFA),
      ),
    );
  }
}

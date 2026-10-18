import 'package:flutter/material.dart';

import '../models/cash_control.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'tender_stat_card.dart';
import 'app_close_button.dart';

/// Opens a slide-in side panel showing movements for [tender].
/// Pass [tender] = null to show all movements.
void showTenderMovementsPanel(
  BuildContext context, {
  required List<CashMovement> movements,
  required PaymentTender? tender,
  required bool isDark,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      pageBuilder: (_, __, ___) => TenderMovementsPanel(
        movements: movements,
        tender: tender,
        isDark: isDark,
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

enum _TypeFilter { all, cashIn, cashOut, adjustment }

class TenderMovementsPanel extends StatefulWidget {
  const TenderMovementsPanel({
    super.key,
    required this.movements,
    required this.tender,
    required this.isDark,
  });

  final List<CashMovement> movements;
  final PaymentTender? tender;
  final bool isDark;

  @override
  State<TenderMovementsPanel> createState() => _TenderMovementsPanelState();
}

class _TenderMovementsPanelState extends State<TenderMovementsPanel> {
  _TypeFilter _typeFilter = _TypeFilter.all;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CashMovement> get _filtered {
    var list = widget.tender == null
        ? widget.movements
        : widget.movements
            .where((m) => m.tender == widget.tender)
            .toList();

    list = switch (_typeFilter) {
      _TypeFilter.cashIn =>
        list.where((m) => m.type == CashMovementType.cashIn).toList(),
      _TypeFilter.cashOut =>
        list.where((m) => m.type == CashMovementType.cashOut).toList(),
      _TypeFilter.adjustment =>
        list.where((m) => m.type == CashMovementType.adjustment).toList(),
      _TypeFilter.all => list,
    };

    if (_query.isNotEmpty) {
      list = list
          .where((m) =>
              m.description.toLowerCase().contains(_query) ||
              (m.linkedTableNumber?.toLowerCase().contains(_query) ?? false) ||
              (m.linkedWaiterName?.toLowerCase().contains(_query) ?? false))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final isDark = widget.isDark;
    final tender = widget.tender;

    final title = tender?.label ?? 'Tous les mouvements';
    final accentColor = tender != null
        ? paymentTenderColor(tender, isDark: isDark)
        : (isDark ? AppColors.skyBlue : AppColors.primaryBlue);

    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = AppConstants.sidePanelWidth(
        screenWidth, (screenWidth * 0.65).clamp(300.0, 520.0));
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final chipBg =
        isDark ? const Color(0xFF1E2E42) : const Color(0xFFF0F4FA);
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.centerRight,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          if (tender != null) ...[
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(paymentTenderIcon(tender),
                                  size: 18, color: accentColor),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: AppTextStyles.h2(
                                      color: isDark
                                          ? AppColors.warmWhite
                                          : AppColors.nearBlack,
                                    )),
                                const SizedBox(height: 2),
                                Text(
                                  '${filtered.length} mouvement${filtered.length == 1 ? '' : 's'}',
                                  style: AppTextStyles.caption(
                                      color: textSecondary),
                                ),
                              ],
                            ),
                          ),
                          AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                        ],
                      ),
                    ),

                    // ── Search bar ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Rechercher une description…',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: chipBg,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                      ),
                    ),

                    // ── Type filter chips ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final e in [
                              (_TypeFilter.all, 'Tous', null),
                              (_TypeFilter.cashIn, 'Entrée',
                                  AppColors.deepGreen),
                              (_TypeFilter.cashOut, 'Sortie',
                                  AppColors.boldRed),
                              (_TypeFilter.adjustment, 'Ajustement',
                                  AppColors.amber),
                            ]) ...[
                              _TypeChip(
                                label: e.$2,
                                selected: _typeFilter == e.$1,
                                activeColor: e.$3 ?? accentColor,
                                isDark: isDark,
                                onTap: () =>
                                    setState(() => _typeFilter = e.$1),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),

                    Divider(height: 1, color: borderColor),

                    // ── List ──────────────────────────────────────────────────
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long_outlined,
                                      size: 40, color: textSecondary),
                                  const SizedBox(height: 12),
                                  Text(
                                    _query.isNotEmpty
                                        ? 'Aucun résultat pour « $_query »'
                                        : 'Aucun mouvement pour ce filtre.',
                                    style: AppTextStyles.body(
                                        color: textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: borderColor),
                              itemBuilder: (context, i) => _MovementRow(
                                movement: filtered[i],
                                isDark: isDark,
                                accentColor: accentColor,
                              ),
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
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color activeColor;
  final bool isDark;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.45)
                : (isDark
                    ? AppColors.darkBorder
                    : const Color(0xFFD8E0EE)),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption(
            color: selected
                ? activeColor
                : (isDark ? AppColors.coolGray : AppColors.darkGray),
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.isDark,
    required this.accentColor,
  });

  final CashMovement movement;
  final bool isDark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isOut = m.type == CashMovementType.cashOut;
    final isAdj = m.type == CashMovementType.adjustment;
    final color = isOut
        ? AppColors.boldRed
        : isAdj
            ? AppColors.amber
            : AppColors.deepGreen;
    final icon = isOut
        ? Icons.north_east
        : isAdj
            ? Icons.tune
            : Icons.south_west;

    final usd = tenderUsesUsd(m.tender);
    String money(double value) => usd
        ? CurrencyFormatter.usd(value)
        : CurrencyFormatter.local(context, value);
    final raw = isAdj
        ? (usd ? m.amountUsd : m.amountHtg)
        : (usd ? m.totalUsd : m.totalHtg);
    final sign = isOut
        ? '−'
        : isAdj
            ? (m.adjustmentAddsToDrawer ? '+' : '−')
            : '+';
    final amtHtg = '$sign ${money(raw.abs())}';

    final timeStr =
        '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}';

    final textSecondary =
        isDark ? AppColors.coolGray : AppColors.darkGray;

    final subtitle = [
      if (isAdj) m.adjustmentAddsToDrawer ? 'Ajouter' : 'Retirer',
      if (m.linkedTableNumber != null) m.linkedTableNumber!,
      if (m.linkedWaiterName != null) m.linkedWaiterName!,
      timeStr,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.description,
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ).copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.caption(color: textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amtHtg,
            style: AppTextStyles.body(color: color)
                .copyWith(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

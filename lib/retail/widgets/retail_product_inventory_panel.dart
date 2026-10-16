import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

/// Opens the product inventory “account” view.
/// On narrow viewports, opens as a **full-screen sliding panel** (not a bottom sheet).
Future<void> showRetailProductInventorySheet(
  BuildContext context,
  MockProduct product,
) async {
  final isNarrow =
      MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isNarrow) {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (ctx, animation, secondary) {
          return Scaffold(
            backgroundColor:
                isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
            body: RetailProductInventoryPanel(product: product),
          );
        },
        transitionsBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    return;
  }

  // Tablet / desktop: right-side panel (never a modal bottom sheet).
  final screenW = MediaQuery.sizeOf(context).width;
  final panelW = AppConstants.retailInventoryDetailPanelWidth(screenW);
  final h = MediaQuery.sizeOf(context).height;

  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: AppConstants.animNormal,
      reverseTransitionDuration: AppConstants.animNormal,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelW,
            height: h,
            child: Material(
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              color: isDark ? AppColors.darkSurface : AppColors.white,
              child: RetailProductInventoryPanel(product: product),
            ),
          ),
        );
      },
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

/// Opens only the add-stock form (quantity, received date, supplier, notes).
Future<void> showRetailAddStockSheet(
  BuildContext context,
  MockProduct product,
) async {
  await showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    child: _AddRetailStockSheet(product: product),
  );
}

// ─── Ledger display model ─────────────────────────────────────────────

class RetailLedgerDisplayRow {
  final String id;
  final int delta;
  final DateTime sortKey;
  /// First column — calendar date of the movement (entered / sale day).
  final String dateLabel;
  final String title;
  /// Second column — extra context (supplier, notes, etc.).
  final String subtitle;
  final int? inQty;
  final int? outQty;
  final RetailStockMovementKind kind;

  RetailLedgerDisplayRow._({
    required this.id,
    required this.delta,
    required this.sortKey,
    required this.dateLabel,
    required this.title,
    required this.subtitle,
    this.inQty,
    this.outQty,
    required this.kind,
  });

  factory RetailLedgerDisplayRow.fromMovement(RetailStockMovement m) {
    switch (m.kind) {
      case RetailStockMovementKind.stockIn:
        return RetailLedgerDisplayRow._(
          id: m.id,
          delta: m.quantityDelta,
          sortKey: m.enteredAt,
          dateLabel: DateFormatter.shortDate(
            DateTime(m.enteredAt.year, m.enteredAt.month, m.enteredAt.day),
          ),
          title: 'Stock in',
          subtitle: _stockInDetails(m),
          inQty: m.quantityDelta,
          outQty: null,
          kind: RetailStockMovementKind.stockIn,
        );
      case RetailStockMovementKind.sale:
        final d = DateTime(m.receivedAt.year, m.receivedAt.month, m.receivedAt.day);
        return RetailLedgerDisplayRow.saleDayAggregate(d, m.quantityDelta);
      case RetailStockMovementKind.adjustment:
        final isUp = m.quantityDelta >= 0;
        return RetailLedgerDisplayRow._(
          id: m.id,
          delta: m.quantityDelta,
          sortKey: m.enteredAt,
          dateLabel: DateFormatter.shortDate(
            DateTime(m.enteredAt.year, m.enteredAt.month, m.enteredAt.day),
          ),
          title: 'Adjustment',
          subtitle: m.notes ?? (isUp ? 'Increase' : 'Decrease'),
          inQty: isUp ? m.quantityDelta : null,
          outQty: isUp ? null : -m.quantityDelta,
          kind: RetailStockMovementKind.adjustment,
        );
    }
  }

  factory RetailLedgerDisplayRow.saleDayAggregate(DateTime day, int qtyDelta) {
    final d = DateTime(day.year, day.month, day.day);
    return RetailLedgerDisplayRow._(
      id: 'sale_day_${d.millisecondsSinceEpoch}',
      delta: qtyDelta,
      sortKey: DateTime(day.year, day.month, day.day, 23, 59, 59),
      dateLabel: DateFormatter.shortDate(d),
      title: 'Sales (POS)',
      subtitle: 'Daily total',
      inQty: null,
      outQty: -qtyDelta,
      kind: RetailStockMovementKind.sale,
    );
  }

  /// Details column only — date is shown in [dateLabel].
  static String _stockInDetails(RetailStockMovement m) {
    final supplier = m.supplierName?.trim();
    final parts = <String>[];
    if (supplier != null && supplier.isNotEmpty) {
      parts.add(supplier);
    }
    final recDay = DateTime(m.receivedAt.year, m.receivedAt.month, m.receivedAt.day);
    final entDay = DateTime(m.enteredAt.year, m.enteredAt.month, m.enteredAt.day);
    if (recDay != entDay) {
      parts.add('Received ${DateFormatter.shortDate(m.receivedAt)}');
    }
    parts.add('Entered ${DateFormatter.timeOfDay(m.enteredAt)}');
    if (m.notes != null && m.notes!.trim().isNotEmpty) {
      parts.add(m.notes!.trim());
    }
    return parts.join(' · ');
  }
}

List<({RetailLedgerDisplayRow row, int balanceAfter})> _buildLedgerRows({
  required int productId,
  required List<RetailStockMovement> movements,
  required int currentStock,
}) {
  final raw = movements.where((m) => m.productId == productId).toList();

  final saleByDay = <DateTime, int>{};
  final nonSale = <RetailStockMovement>[];
  for (final m in raw) {
    if (m.kind == RetailStockMovementKind.sale) {
      final d = DateTime(m.receivedAt.year, m.receivedAt.month, m.receivedAt.day);
      saleByDay[d] = (saleByDay[d] ?? 0) + m.quantityDelta;
    } else {
      nonSale.add(m);
    }
  }

  final displayRows = <RetailLedgerDisplayRow>[];
  for (final m in nonSale) {
    displayRows.add(RetailLedgerDisplayRow.fromMovement(m));
  }
  for (final e in saleByDay.entries) {
    if (e.value != 0) {
      displayRows.add(RetailLedgerDisplayRow.saleDayAggregate(e.key, e.value));
    }
  }

  displayRows.sort((a, b) => a.sortKey.compareTo(b.sortKey));

  var cum = 0;
  final balances = <int>[];
  for (final r in displayRows) {
    cum += r.delta;
    balances.add(cum);
  }

  final out = <({RetailLedgerDisplayRow row, int balanceAfter})>[];
  for (var i = displayRows.length - 1; i >= 0; i--) {
    out.add((row: displayRows[i], balanceAfter: balances[i]));
  }
  return out;
}

String _inventoryMonthName(int month) =>
    DateFormat.MMMM().format(DateTime(2000, month));

String _ledgerMovementKindMenuLabel(RetailStockMovementKind k) {
  switch (k) {
    case RetailStockMovementKind.sale:
      return 'Sales';
    case RetailStockMovementKind.stockIn:
      return 'Stock in';
    case RetailStockMovementKind.adjustment:
      return 'Adjustment';
  }
}

String _ledgerMovementKindEmptyPhrase(RetailStockMovementKind k) {
  switch (k) {
    case RetailStockMovementKind.sale:
      return 'sales';
    case RetailStockMovementKind.stockIn:
      return 'stock in';
    case RetailStockMovementKind.adjustment:
      return 'adjustments';
  }
}

// ─── Panel ────────────────────────────────────────────────────────────

class RetailProductInventoryPanel extends ConsumerStatefulWidget {
  const RetailProductInventoryPanel({
    super.key,
    required this.product,
    this.embedded = false,
    this.onClose,
  });

  final MockProduct product;
  final bool embedded;

  /// When set (e.g. desktop drawer), shows a close control in the header.
  final VoidCallback? onClose;

  @override
  ConsumerState<RetailProductInventoryPanel> createState() =>
      _RetailProductInventoryPanelState();
}

class _RetailProductInventoryPanelState
    extends ConsumerState<RetailProductInventoryPanel> {
  /// 1–12: which month of [DateTime.now().year] to show in the ledger.
  int _ledgerMonth = DateTime.now().month;

  /// `null` = all movement kinds.
  RetailStockMovementKind? _movementKindFilter;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final products = ref.watch(mockProductsProvider);
    final ledger = ref.watch(retailInventoryLedgerProvider);
    MockProduct current = widget.product;
    for (final p in products) {
      if (p.id == widget.product.id) {
        current = p;
        break;
      }
    }

    final allRows = _buildLedgerRows(
      productId: current.id,
      movements: ledger,
      currentStock: current.stockQuantity,
    );

    final ledgerYear = DateTime.now().year;
    final monthRows = allRows
        .where(
          (e) =>
              e.row.sortKey.year == ledgerYear &&
              e.row.sortKey.month == _ledgerMonth,
        )
        .toList();
    final rows = _movementKindFilter == null
        ? monthRows
        : monthRows
            .where((e) => e.row.kind == _movementKindFilter)
            .toList();

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    int salesToday = 0;
    for (final m in ledger.where((m) => m.productId == current.id && m.kind == RetailStockMovementKind.sale)) {
      final d = DateTime(m.receivedAt.year, m.receivedAt.month, m.receivedAt.day);
      if (d == todayDate) {
        salesToday += -m.quantityDelta;
      }
    }

    final scrollHorizontalPad = widget.embedded
        ? 0.0
        : AppConstants.spacing24;

    final scrollContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          if (!widget.embedded) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    current.name,
                    style: AppTextStyles.h2(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(current.category, style: AppTextStyles.caption()),
            const SizedBox(height: AppConstants.spacing8),
            _InlineStockBadges(
              stockQuantity: current.stockQuantity,
              salesToday: salesToday,
              isDark: isDark,
            ),
            const SizedBox(height: AppConstants.spacing16),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.name,
                        style: AppTextStyles.h2(
                          color:
                              isDark ? AppColors.warmWhite : AppColors.nearBlack,
                        ),
                      ),
                      Text(current.category, style: AppTextStyles.caption()),
                      const SizedBox(height: AppConstants.spacing8),
                      _InlineStockBadges(
                        stockQuantity: current.stockQuantity,
                        salesToday: salesToday,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing16),
          ],
          LayoutBuilder(
            builder: (context, c) {
              final thin = c.maxWidth < 420;
              final title = Text(
                'Movement history',
                style: AppTextStyles.h3(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              );
              final yearLabel = Text(
                '$ledgerYear',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              );
              final monthPicker = _LedgerMonthDropdown(
                month: _ledgerMonth,
                isDark: isDark,
                onChanged: (m) => setState(() => _ledgerMonth = m),
              );
              final kindPicker = _LedgerMovementKindDropdown(
                kind: _movementKindFilter,
                isDark: isDark,
                onChanged: (k) => setState(() => _movementKindFilter = k),
              );
              if (thin) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: AppConstants.spacing8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppConstants.spacing8,
                      runSpacing: AppConstants.spacing8,
                      children: [
                        yearLabel,
                        monthPicker,
                        kindPicker,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: title),
                  yearLabel,
                  const SizedBox(width: AppConstants.spacing8),
                  monthPicker,
                  const SizedBox(width: AppConstants.spacing8),
                  kindPicker,
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.spacing12),
          if (allRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing24),
              child: Text(
                'No stock movements yet.',
                style: AppTextStyles.body(color: isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
            )
          else if (monthRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing24),
              child: Text(
                'No movements in ${_inventoryMonthName(_ledgerMonth)} $ledgerYear.',
                style: AppTextStyles.body(color: isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing24),
              child: Text(
                'No ${_ledgerMovementKindEmptyPhrase(_movementKindFilter!)} for ${_inventoryMonthName(_ledgerMonth)} $ledgerYear.',
                style: AppTextStyles.body(color: isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
            )
          else
            _LedgerTable(rows: rows, isDark: isDark),
          SizedBox(height: widget.embedded ? AppConstants.spacing8 : AppConstants.spacing16),
        ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: scrollHorizontalPad),
            child: scrollContent,
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.6)
              : AppColors.darkGray.withValues(alpha: 0.2),
        ),
        _InventoryActionBar(
          isDark: isDark,
          onAddStock: () => _openAddStock(context, ref, current),
          onAdjust: () => _openAdjust(context, ref, current),
          bottomInset: MediaQuery.viewInsetsOf(context).bottom,
        ),
      ],
    );

    if (widget.embedded) {
      return body;
    }

    final h = MediaQuery.sizeOf(context).height;
    final isMobile =
        MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;

    if (isMobile) {
      return SizedBox(
        height: h,
        child: SafeArea(
          child: body,
        ),
      );
    }

    return SizedBox(
      height: h,
      child: body,
    );
  }

  Future<void> _openAddStock(
    BuildContext context,
    WidgetRef ref,
    MockProduct product,
  ) async {
    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      child: _AddRetailStockSheet(product: product),
    );
  }

  Future<void> _openAdjust(
    BuildContext context,
    WidgetRef ref,
    MockProduct product,
  ) async {
    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      child: _AdjustRetailStockSheet(product: product),
    );
  }
}

class _InlineStockBadges extends StatelessWidget {
  const _InlineStockBadges({
    required this.stockQuantity,
    required this.salesToday,
    required this.isDark,
  });

  final int stockQuantity;
  final int salesToday;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? AppColors.darkSurface : AppColors.white;

    Widget chip({
      required IconData icon,
      required String label,
      required String value,
      required Color accent,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: AppTextStyles.caption(color: accent).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: AppConstants.spacing8,
      runSpacing: AppConstants.spacing8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(
          icon: Icons.inventory_2_outlined,
          label: 'Stock',
          value: '$stockQuantity units',
          accent: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
        ),
        chip(
          icon: Icons.point_of_sale_outlined,
          label: 'Sales today',
          value: '$salesToday',
          accent: AppColors.amber,
        ),
      ],
    );
  }
}

class _LedgerMonthDropdown extends StatelessWidget {
  const _LedgerMonthDropdown({
    required this.month,
    required this.isDark,
    required this.onChanged,
  });

  final int month;
  final bool isDark;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.darkBorder : AppColors.darkGray.withValues(alpha: 0.3);
    final fill = isDark ? AppColors.darkSurface : AppColors.warmOffWhite;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        border: Border.all(color: border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: month,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
          dropdownColor: isDark ? AppColors.darkSurface : AppColors.white,
          style: AppTextStyles.caption(
            color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
          ).copyWith(fontWeight: FontWeight.w600),
          items: List.generate(
            12,
            (i) {
              final m = i + 1;
              return DropdownMenuItem<int>(
                value: m,
                child: Text(_inventoryMonthName(m)),
              );
            },
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _LedgerMovementKindDropdown extends StatelessWidget {
  const _LedgerMovementKindDropdown({
    required this.kind,
    required this.isDark,
    required this.onChanged,
  });

  final RetailStockMovementKind? kind;
  final bool isDark;
  final ValueChanged<RetailStockMovementKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.darkBorder : AppColors.darkGray.withValues(alpha: 0.3);
    final fill = isDark ? AppColors.darkSurface : AppColors.warmOffWhite;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        border: Border.all(color: border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RetailStockMovementKind?>(
          value: kind,
          isDense: true,
          hint: Text(
            'Type',
            style: AppTextStyles.caption(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
          ),
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
          dropdownColor: isDark ? AppColors.darkSurface : AppColors.white,
          style: AppTextStyles.caption(
            color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
          ).copyWith(fontWeight: FontWeight.w600),
          items: [
            DropdownMenuItem<RetailStockMovementKind?>(
              value: null,
              child: Text(
                'All types',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              ),
            ),
            DropdownMenuItem<RetailStockMovementKind?>(
              value: RetailStockMovementKind.sale,
              child: Text(_ledgerMovementKindMenuLabel(RetailStockMovementKind.sale)),
            ),
            DropdownMenuItem<RetailStockMovementKind?>(
              value: RetailStockMovementKind.stockIn,
              child: Text(_ledgerMovementKindMenuLabel(RetailStockMovementKind.stockIn)),
            ),
            DropdownMenuItem<RetailStockMovementKind?>(
              value: RetailStockMovementKind.adjustment,
              child: Text(_ledgerMovementKindMenuLabel(RetailStockMovementKind.adjustment)),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({
    required this.rows,
    required this.isDark,
  });

  final List<({RetailLedgerDisplayRow row, int balanceAfter})> rows;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final headerColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 400;
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows.map((e) => _LedgerTile(row: e.row, balance: e.balanceAfter, isDark: isDark)).toList(),
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Date',
                            style: AppTextStyles.caption(color: headerColor).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Details',
                            style: AppTextStyles.caption(color: headerColor).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            'In',
                            textAlign: TextAlign.end,
                            style: AppTextStyles.caption(color: headerColor).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            'Out',
                            textAlign: TextAlign.end,
                            style: AppTextStyles.caption(color: headerColor).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            'Balance',
                            textAlign: TextAlign.end,
                            style: AppTextStyles.caption(color: headerColor).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    ...List.generate(rows.length, (i) {
                      final e = rows[i];
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    e.row.dateLabel,
                                    style: AppTextStyles.caption(
                                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                                    ).copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.row.title,
                                        style: AppTextStyles.body(
                                          color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                                        ).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      if (e.row.subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          e.row.subtitle,
                                          style: AppTextStyles.caption(),
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    e.row.inQty != null ? '+${e.row.inQty}' : '—',
                                    textAlign: TextAlign.end,
                                    style: AppTextStyles.caption(color: AppColors.deepGreen),
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    e.row.outQty != null ? '−${e.row.outQty}' : '—',
                                    textAlign: TextAlign.end,
                                    style: AppTextStyles.caption(color: AppColors.boldRed),
                                  ),
                                ),
                                SizedBox(
                                  width: 56,
                                  child: Text(
                                    '${e.balanceAfter}',
                                    textAlign: TextAlign.end,
                                    style: AppTextStyles.body(
                                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < rows.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.row,
    required this.balance,
    required this.isDark,
  });

  final RetailLedgerDisplayRow row;
  final int balance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing8),
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground.withValues(alpha: 0.45) : AppColors.lightBlue.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        border: Border.all(
          color: (isDark ? AppColors.coolGray : AppColors.darkGray).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  row.dateLabel,
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (row.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(row.subtitle, style: AppTextStyles.caption()),
                    ],
                  ],
                ),
              ),
              Text(
                '$balance',
                style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                row.inQty != null ? 'In +${row.inQty}' : 'In —',
                style: AppTextStyles.caption(color: AppColors.deepGreen),
              ),
              const SizedBox(width: 16),
              Text(
                row.outQty != null ? 'Out −${row.outQty}' : 'Out —',
                style: AppTextStyles.caption(color: AppColors.boldRed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pinned to the bottom of the inventory panel (scroll content sits above).
class _InventoryActionBar extends StatelessWidget {
  const _InventoryActionBar({
    required this.isDark,
    required this.onAddStock,
    required this.onAdjust,
    required this.bottomInset,
  });

  final bool isDark;
  final VoidCallback onAddStock;
  final VoidCallback onAdjust;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    return Material(
      color: bg,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spacing16,
          AppConstants.spacing8,
          AppConstants.spacing16,
          AppConstants.spacing8 + bottomInset,
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 420;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: 'Add stock',
                    icon: Icons.add_circle_outline,
                    onPressed: onAddStock,
                    fullWidth: true,
                    compact: true,
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  AppButton(
                    label: 'Adjust balance',
                    icon: Icons.tune_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: onAdjust,
                    fullWidth: true,
                    compact: true,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Add stock',
                    icon: Icons.add_circle_outline,
                    onPressed: onAddStock,
                    fullWidth: true,
                    compact: true,
                  ),
                ),
                const SizedBox(width: AppConstants.spacing8),
                Expanded(
                  child: AppButton(
                    label: 'Adjust balance',
                    icon: Icons.tune_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: onAdjust,
                    fullWidth: true,
                    compact: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AddRetailStockSheet extends ConsumerStatefulWidget {
  const _AddRetailStockSheet({required this.product});

  final MockProduct product;

  @override
  ConsumerState<_AddRetailStockSheet> createState() => _AddRetailStockSheetState();
}

class _AddRetailStockSheetState extends ConsumerState<_AddRetailStockSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _supplierCtrl;
  DateTime _receivedDate = DateTime.now();
  bool _supplierInited = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _supplierCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_supplierInited) {
      final suppliers = ref.read(mockSuppliersProvider);
      if (suppliers.isNotEmpty) {
        _supplierCtrl.text = suppliers.first.name;
      }
      _supplierInited = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suppliers = ref.watch(mockSuppliersProvider);

    final pad = EdgeInsets.only(
      left: AppConstants.spacing24,
      right: AppConstants.spacing24,
      bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
    );

    return Padding(
      padding: pad,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add stock',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.product.name,
              style: AppTextStyles.caption(),
            ),
            const SizedBox(height: AppConstants.spacing24),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: InputFormatters.digitsOnly,
              decoration: InputDecoration(
                labelText: 'Quantity',
                suffixText: 'units',
                filled: true,
                fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _receivedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _receivedDate = picked);
              },
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Received date',
                  filled: true,
                  fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(DateFormatter.shortDate(_receivedDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Entered in system will be recorded when you save (now).',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: _supplierCtrl,
              decoration: InputDecoration(
                labelText: 'Supplier',
                filled: true,
                fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            if (suppliers.isNotEmpty) ...[
              const SizedBox(height: AppConstants.spacing8),
              Text('Quick select', style: AppTextStyles.caption()),
              const SizedBox(height: AppConstants.spacing8),
              Wrap(
                spacing: AppConstants.spacing8,
                runSpacing: AppConstants.spacing8,
                children: suppliers
                    .map(
                      (s) => ActionChip(
                        label: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(),
                        ),
                        onPressed: () => setState(() => _supplierCtrl.text = s.name),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                filled: true,
                fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: AppConstants.buttonHeight / 2),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Save stock in',
                    icon: Icons.save_outlined,
                    onPressed: () {
                      final q = int.tryParse(_qtyCtrl.text) ?? 0;
                      if (q <= 0) return;
                      final sup = _supplierCtrl.text.trim();
                      if (sup.isEmpty) return;
                      final received = DateTime(
                        _receivedDate.year,
                        _receivedDate.month,
                        _receivedDate.day,
                      );
                      ref.read(retailInventoryLedgerProvider.notifier).addStockIn(
                            productId: widget.product.id,
                            quantity: q,
                            receivedAt: received,
                            supplierName: sup,
                            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
                          );
                      Navigator.pop(context);
                    },
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustRetailStockSheet extends ConsumerStatefulWidget {
  const _AdjustRetailStockSheet({required this.product});

  final MockProduct product;

  @override
  ConsumerState<_AdjustRetailStockSheet> createState() => _AdjustRetailStockSheetState();
}

class _AdjustRetailStockSheetState extends ConsumerState<_AdjustRetailStockSheet> {
  final _amtCtrl = TextEditingController();
  final _noteCtrl = TextEditingController(text: 'Inventory correction');
  bool _isAdd = true;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pad = EdgeInsets.only(
      left: AppConstants.spacing24,
      right: AppConstants.spacing24,
      bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
    );

    return Padding(
      padding: pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adjust balance',
            style: AppTextStyles.h2(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.product.name,
            style: AppTextStyles.caption(),
          ),
          const SizedBox(height: AppConstants.spacing24),
          Row(
            children: [
              Expanded(
                child: _AdjChip(
                  label: 'Increase',
                  icon: Icons.add_circle_outline,
                  selected: _isAdd,
                  isDark: isDark,
                  onTap: () => setState(() => _isAdd = true),
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: _AdjChip(
                  label: 'Decrease',
                  icon: Icons.remove_circle_outline,
                  selected: !_isAdd,
                  isDark: isDark,
                  onTap: () => setState(() => _isAdd = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          TextField(
            controller: _amtCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: InputFormatters.digitsOnly,
            decoration: InputDecoration(
              labelText: 'Units',
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacing16),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Reason',
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacing24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppConstants.buttonHeight / 2),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Apply',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final n = int.tryParse(_amtCtrl.text) ?? 0;
                    if (n <= 0) return;
                    final signed = _isAdd ? n : -n;
                    ref.read(retailInventoryLedgerProvider.notifier).adjust(
                          productId: widget.product.id,
                          signedDelta: signed,
                          notes: _noteCtrl.text.trim(),
                        );
                    Navigator.pop(context);
                  },
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdjChip extends StatelessWidget {
  const _AdjChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spacing12,
            horizontal: AppConstants.spacing12,
          ),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? AppColors.skyBlue.withValues(alpha: 0.2)
                    : AppColors.primaryBlue.withValues(alpha: 0.12))
                : (isDark ? AppColors.darkBackground : AppColors.warmOffWhite),
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            border: Border.all(
              color: selected
                  ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                  : (isDark ? AppColors.coolGray : AppColors.darkGray)
                      .withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.primaryBlue : AppColors.darkGray),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body(
                    color: selected ? AppColors.primaryBlue : AppColors.nearBlack,
                  ).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

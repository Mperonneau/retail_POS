import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tip_management.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

void showTipsHistoryPanel(BuildContext context, bool isDark) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      pageBuilder: (_, __, ___) => TipsHistoryPanel(isDark: isDark),
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

class TipsHistoryPanel extends ConsumerStatefulWidget {
  final bool isDark;
  const TipsHistoryPanel({super.key, required this.isDark});

  @override
  ConsumerState<TipsHistoryPanel> createState() => _TipsHistoryPanelState();
}

class _TipsHistoryPanelState extends ConsumerState<TipsHistoryPanel> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  DateTime? _from;
  DateTime? _to;
  bool _isCustomRange = false;
  int _extraWeeks = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Default window: past 7 days (+ extra weeks loaded via "Charger plus")
  DateTime get _defaultFrom {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 6 + _extraWeeks * 7));
  }

  DateTime get _defaultTo {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  DateTime get _effectiveFrom =>
      _isCustomRange ? DateTime(_from!.year, _from!.month, _from!.day) : _defaultFrom;

  DateTime get _effectiveTo => _isCustomRange
      ? DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59)
      : _defaultTo;

  bool _inWindow(TipEntry e) =>
      !e.timestamp.isBefore(_effectiveFrom) &&
      !e.timestamp.isAfter(_effectiveTo);

  String get _defaultRangeLabel {
    if (_extraWeeks == 0) return 'Past 7 days';
    return '${_shortDate(_defaultFrom)} – ${_shortDate(_defaultTo)}';
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_from ?? now.subtract(const Duration(days: 6)))
          : (_to ?? now),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _isCustomRange = true;
      if (isFrom) {
        _from = picked;
        _to ??= now;
      } else {
        _to = picked;
        _from ??= now.subtract(const Duration(days: 6));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tipState = ref.watch(tipProvider);
    final isDark = widget.isDark;

    // All entries sorted newest first
    final all = [...tipState.entries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Name filter
    final nameFiltered = _query.isEmpty
        ? all
        : all
            .where((e) =>
                e.waiterName.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Date window filter
    final filtered = nameFiltered.where(_inWindow).toList();

    // Are there older entries outside the current window?
    final hasOlder = !_isCustomRange &&
        nameFiltered.any((e) => e.timestamp.isBefore(_effectiveFrom));

    // Build grouped list (date separators + entry items)
    final items = _buildGroupedItems(filtered);

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    final panelWidth =
        isWide ? (screenWidth * 0.62).clamp(400.0, 580.0) : screenWidth;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);

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
                    _buildHeader(context, isDark, borderColor),

                    // ── Search ───────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SearchField(
                        controller: _searchCtrl,
                        isDark: isDark,
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),

                    // ── Date filter bar ───────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: _DateFilterBar(
                        from: _isCustomRange ? _from : null,
                        to: _isCustomRange ? _to : null,
                        defaultLabel: _defaultRangeLabel,
                        isDark: isDark,
                        onPickFrom: () =>
                            _pickDate(context, isFrom: true),
                        onPickTo: () =>
                            _pickDate(context, isFrom: false),
                        onClear: () => setState(() {
                          _from = null;
                          _to = null;
                          _isCustomRange = false;
                          _extraWeeks = 0;
                        }),
                      ),
                    ),

                    Divider(height: 1, color: borderColor),

                    // ── List ─────────────────────────────────────────────
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState(isDark)
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount:
                                  items.length + (hasOlder ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i == items.length) {
                                  return _LoadMoreButton(
                                    isDark: isDark,
                                    onTap: () =>
                                        setState(() => _extraWeeks++),
                                  );
                                }
                                final item = items[i];
                                if (item is _DateLabel) {
                                  return _DateSeparator(
                                    label: item.label,
                                    isDark: isDark,
                                  );
                                }
                                return _EntryRow(
                                  entry: (item as _EntryItem).entry,
                                  isDark: isDark,
                                );
                              },
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

  Widget _buildHeader(
      BuildContext context, bool isDark, Color borderColor) {
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final iconColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Back to tips panel
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E2E42)
                    : const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: iconColor),
            ),
          ),
          const SizedBox(width: 12),

          // Icon badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.skyBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_rounded,
                color: AppColors.skyBlue, size: 18),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Historique des pourboires',
                    style: AppTextStyles.h2(color: textColor)),
                Text('Tous les mouvements de pourboires',
                    style: AppTextStyles.caption()),
              ],
            ),
          ),

          // Close
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: iconColor,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final color = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 48, color: color),
            const SizedBox(height: 14),
            Text('Aucune entrée trouvée.',
                style: AppTextStyles.body(color: color)),
            const SizedBox(height: 6),
            Text(
              'Modifiez la période\nou la recherche.',
              style: AppTextStyles.caption().copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<_ListItem> _buildGroupedItems(List<TipEntry> entries) {
    final result = <_ListItem>[];
    String? lastLabel;
    for (final entry in entries) {
      final label = _dayLabel(entry.timestamp);
      if (label != lastLabel) {
        result.add(_DateLabel(label));
        lastLabel = label;
      }
      result.add(_EntryItem(entry));
    }
    return result;
  }
}

// ─── Internal list item types ─────────────────────────────────────────────────

abstract class _ListItem {}

class _DateLabel extends _ListItem {
  final String label;
  _DateLabel(this.label);
}

class _EntryItem extends _ListItem {
  final TipEntry entry;
  _EntryItem(this.entry);
}

// ─── Date separator ───────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final String label;
  final bool isDark;
  const _DateSeparator({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pillBg =
        isDark ? const Color(0xFF1E2E42) : const Color(0xFFEEF3FF);
    final pillBorder =
        isDark ? AppColors.darkBorder : const Color(0xFFCCD5F0);
    final labelColor =
        isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final lineColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: pillBorder),
            ),
            child: Text(
              label,
              style: AppTextStyles.caption(color: labelColor).copyWith(
                  fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }
}

// ─── Entry row card ───────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  final TipEntry entry;
  final bool isDark;
  const _EntryRow({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isPayout = entry.type == TipEntryType.payout;
    final isAdj = entry.type == TipEntryType.adjustment;
    final isNeg = entry.amountHtg < 0;

    final typeColor = isPayout
        ? AppColors.deepGreen
        : isAdj
            ? (isNeg ? AppColors.boldRed : AppColors.skyBlue)
            : AppColors.amber;

    final typeLabel =
        isPayout ? 'Payout' : isAdj ? 'Adj.' : 'Tip';
    final sign =
        isPayout ? '−' : (isAdj && isNeg ? '−' : '+');
    final amtHtg = entry.amountHtg.abs();
    final amtUsd = entry.amountUsd.abs();

    final cardBorder =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final cardBg =
        isDark ? const Color(0xFF1A2535) : AppColors.white;
    final textColor =
        isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final subColor =
        isDark ? AppColors.coolGray : AppColors.darkGray;

    final h = entry.timestamp.hour.toString().padLeft(2, '0');
    final m = entry.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: cardBorder),
          boxShadow: isDark ? [] : AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type badge ──────────────────────────────────────────
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  typeLabel,
                  style: AppTextStyles.caption(color: typeColor)
                      .copyWith(
                          fontSize: 9, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // ── Content ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Waiter name with avatar initial
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            entry.waiterName[0].toUpperCase(),
                            style: AppTextStyles.caption(
                                    color: AppColors.amber)
                                .copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        entry.waiterName,
                        style: AppTextStyles.body(color: textColor)
                            .copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Reason
                  Text(
                    entry.reason,
                    style: AppTextStyles.body(color: subColor)
                        .copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),

                  // Table + time
                  Row(
                    children: [
                      if (entry.linkedTable != null) ...[
                        Icon(Icons.table_restaurant_outlined,
                            size: 11, color: subColor),
                        const SizedBox(width: 2),
                        Text(
                          entry.linkedTable!,
                          style: AppTextStyles.caption(color: subColor)
                              .copyWith(fontSize: 10),
                        ),
                        Text(' · ',
                            style: AppTextStyles.caption(color: subColor)
                                .copyWith(fontSize: 10)),
                      ],
                      Icon(Icons.access_time_rounded,
                          size: 11, color: subColor),
                      const SizedBox(width: 2),
                      Text(
                        '$h:$m',
                        style: AppTextStyles.caption(color: subColor)
                            .copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Amounts ─────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$sign${CurrencyFormatter.local(context, amtHtg)}',
                  style: AppTextStyles.body(color: typeColor).copyWith(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sign\$${amtUsd.toStringAsFixed(2)}',
                  style: AppTextStyles.caption(
                      color: typeColor.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC);
    final fillColor =
        isDark ? const Color(0xFF1E2E42) : const Color(0xFFF5F5F5);
    final textColor =
        isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final hintColor =
        isDark ? AppColors.coolGray : AppColors.darkGray;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, color: textColor),
      decoration: InputDecoration(
        hintText: 'Rechercher par nom de serveuse…',
        hintStyle: TextStyle(fontSize: 13, color: hintColor),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: hintColor),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              width: 1.5),
        ),
      ),
    );
  }
}

// ─── Date filter bar ──────────────────────────────────────────────────────────

class _DateFilterBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final String defaultLabel;
  final bool isDark;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClear;

  const _DateFilterBar({
    required this.from,
    required this.to,
    required this.defaultLabel,
    required this.isDark,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = from != null || to != null;
    final labelColor =
        isDark ? AppColors.coolGray : AppColors.darkGray;
    final activeColor =
        isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: 13, color: labelColor),
        const SizedBox(width: 6),

        if (!isCustom) ...[
          // Default range chip (tap to start customizing)
          GestureDetector(
            onTap: onPickFrom,
            child: _Chip(
              label: defaultLabel,
              color: activeColor,
              isDark: isDark,
              filled: false,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '— touchez pour filtrer',
            style: AppTextStyles.caption(color: labelColor)
                .copyWith(fontSize: 10),
          ),
        ] else ...[
          // From chip
          GestureDetector(
            onTap: onPickFrom,
            child: _Chip(
              label: from != null ? _shortDate(from!) : 'De',
              color: activeColor,
              isDark: isDark,
              filled: from != null,
              icon: Icons.calendar_month_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('→',
                style: AppTextStyles.caption(color: labelColor)),
          ),
          // To chip
          GestureDetector(
            onTap: onPickTo,
            child: _Chip(
              label: to != null ? _shortDate(to!) : 'À',
              color: activeColor,
              isDark: isDark,
              filled: to != null,
              icon: Icons.calendar_month_outlined,
            ),
          ),
          const Spacer(),
          // Clear
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.boldRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.boldRed.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Effacer',
                style: AppTextStyles.caption(color: AppColors.boldRed)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  final bool filled;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.color,
    required this.isDark,
    this.filled = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? color.withValues(alpha: 0.1)
        : (isDark ? const Color(0xFF1E2E42) : const Color(0xFFF5F5F5));
    final border = filled
        ? color.withValues(alpha: 0.35)
        : (isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC));
    final fg = filled
        ? color
        : (isDark ? AppColors.coolGray : AppColors.darkGray);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.caption(color: fg)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Load more button ─────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _LoadMoreButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.expand_more_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  'Semaine précédente',
                  style: AppTextStyles.body(color: color)
                      .copyWith(
                          fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _dayLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Aujourd\'hui';
  if (diff == 1) return 'Hier';
  return _shortDate(d);
}

String _shortDate(DateTime dt) {
  const months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  const weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
}

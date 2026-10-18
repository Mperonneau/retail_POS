import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cash_control.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'app_close_button.dart';

// ─── Entry point: push as a transparent overlay ───────────────────────────────

void showCashHistoryPanel(
  BuildContext context,
  bool isDark, {
  StateNotifierProvider<CashSessionNotifier, CashControlState>?
      sessionProvider,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      pageBuilder: (_, __, ___) => CashHistoryPanel(
        isDark: isDark,
        sessionProvider: sessionProvider ?? cashSessionProvider,
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

// ─── Panel ────────────────────────────────────────────────────────────────────

class CashHistoryPanel extends ConsumerStatefulWidget {
  final bool isDark;
  final StateNotifierProvider<CashSessionNotifier, CashControlState>
      sessionProvider;
  CashHistoryPanel({
    super.key,
    required this.isDark,
    required this.sessionProvider,
  });

  @override
  ConsumerState<CashHistoryPanel> createState() => _CashHistoryPanelState();
}

class _CashHistoryPanelState extends ConsumerState<CashHistoryPanel> {
  late DateTime _from;
  late DateTime _to;
  bool _isCustomRange = false;
  // Each increment extends the visible window back by 7 days
  int _extraWeeks = 0;

  @override
  void initState() {
    super.initState();
    _from = _currentWeekMonday();
    _to = _currentWeekSaturday();
  }

  // Most recent Monday (inclusive of today if today is Monday)
  static DateTime _currentWeekMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  // Saturday of the current week, capped at today
  static DateTime _currentWeekSaturday() {
    final monday = _currentWeekMonday();
    final saturday = monday.add(const Duration(days: 5));
    final today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return saturday.isAfter(today) ? today : saturday;
  }

  void _resetFilter() {
    setState(() {
      _from = _currentWeekMonday();
      _to = _currentWeekSaturday();
      _isCustomRange = false;
      _extraWeeks = 0;
    });
  }

  // Effective start = _from shifted back by loaded extra weeks
  DateTime get _effectiveFrom =>
      _from.subtract(Duration(days: _extraWeeks * 7));

  // Effective end = end of _to day
  DateTime get _effectiveTo =>
      DateTime(_to.year, _to.month, _to.day, 23, 59, 59);

  bool _inWindow(SessionSummary s) {
    final d = s.session.openedAt;
    return !d.isBefore(_effectiveFrom) && !d.isAfter(_effectiveTo);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
      _isCustomRange = true;
      _extraWeeks = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.sessionProvider);
    final isDark = widget.isDark;

    final filtered =
        state.sessionHistory.where(_inWindow).toList();

    // "Charger plus" is relevant only when not in custom-range mode and
    // there are sessions older than the current effective start
    final hasOlder = !_isCustomRange &&
        state.sessionHistory
            .any((s) => s.session.openedAt.isBefore(_effectiveFrom));

    final totalShown =
        filtered.length + (state.activeSession != null ? 1 : 0);

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    final panelWidth =
        isWide ? (screenWidth * 0.62).clamp(400.0, 580.0) : screenWidth;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;

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
                      title: 'Historique des sessions',
                      subtitle: '$totalShown session(s) affichée(s)',
                      icon: Icons.history_rounded,
                      isDark: isDark,
                    ),

                    // ── Date filter bar ───────────────────────────────────
                    _DateFilterBar(
                      from: _effectiveFrom,
                      to: _to,
                      isCustomRange: _isCustomRange,
                      isDark: isDark,
                      onFromTap: () => _pickDate(isFrom: true),
                      onToTap: () => _pickDate(isFrom: false),
                      onClear: _isCustomRange ? _resetFilter : null,
                    ),

                    // ── List ─────────────────────────────────────────────
                    Expanded(
                      child: (state.activeSession == null &&
                              state.sessionHistory.isEmpty)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history_rounded,
                                        size: 44,
                                        color: isDark
                                            ? AppColors.coolGray
                                            : AppColors.darkGray),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Aucun historique de session.\nOuvrez puis fermez un tiroir pour commencer.',
                                      style: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.coolGray
                                              : AppColors.darkGray),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              children: [
                                // Active session always on top
                                if (state.activeSession != null) ...[
                                  _ActiveSessionCard(
                                      state: state, isDark: isDark),
                                  const SizedBox(height: 12),
                                ],

                                // Section label
                                if (state.activeSession != null &&
                                    filtered.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 4, bottom: 10),
                                    child: Text(
                                      'SESSIONS PRÉCÉDENTES',
                                      style: AppTextStyles.caption(
                                              color: isDark
                                                  ? AppColors.coolGray
                                                  : AppColors.darkGray)
                                          .copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.6),
                                    ),
                                  ),
                                ],

                                // No results in range
                                if (filtered.isEmpty &&
                                    state.activeSession == null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 32),
                                    child: Center(
                                      child: Text(
                                        'Aucune session sur cette période.',
                                        style: AppTextStyles.body(
                                            color: isDark
                                                ? AppColors.coolGray
                                                : AppColors.darkGray),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),

                                // Filtered closed sessions
                                ...filtered.map((s) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _ClosedSessionCard(
                                          summary: s, isDark: isDark),
                                    )),

                                // Load more button
                                if (hasOlder)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: _LoadMoreButton(
                                      isDark: isDark,
                                      onTap: () =>
                                          setState(() => _extraWeeks++),
                                    ),
                                  ),

                                // End-of-history note
                                if (!hasOlder && !_isCustomRange &&
                                    state.sessionHistory.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 8),
                                    child: Center(
                                      child: Text(
                                        'Toutes les sessions sont chargées',
                                        style: AppTextStyles.caption(
                                            color: isDark
                                                ? AppColors.coolGray
                                                : AppColors.darkGray),
                                      ),
                                    ),
                                  ),
                              ],
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

// ─── Date filter bar ──────────────────────────────────────────────────────────

class _DateFilterBar extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final bool isCustomRange;
  final bool isDark;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback? onClear;

  const _DateFilterBar({
    required this.from,
    required this.to,
    required this.isCustomRange,
    required this.isDark,
    required this.onFromTap,
    required this.onToTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final chipBg =
        isDark ? const Color(0xFF1E2E42) : const Color(0xFFF0F4F8);
    final chipBorder =
        isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD);
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final valueColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;

    Widget dateChip(
        String label, DateTime date, VoidCallback onTap, bool highlight) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : chipBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlight
                  ? AppColors.primaryBlue.withValues(alpha: 0.4)
                  : chipBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 12,
                  color: highlight
                      ? AppColors.primaryBlue
                      : labelColor),
              const SizedBox(width: 5),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.caption(color: labelColor)
                        .copyWith(fontSize: 9),
                  ),
                  Text(
                    _shortDate(date),
                    style: AppTextStyles.body(color: valueColor)
                        .copyWith(
                            fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          dateChip('De', from, onFromTap, isCustomRange),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded,
                size: 13, color: labelColor),
          ),
          dateChip('À', to, onToTap, isCustomRange),
          const Spacer(),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.boldRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.boldRed.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded,
                        size: 12, color: AppColors.boldRed),
                    const SizedBox(width: 3),
                    Text('Effacer',
                        style: AppTextStyles.caption(
                                color: AppColors.boldRed)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
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
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD);
    final fg = isDark ? AppColors.coolGray : AppColors.darkGray;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.expand_more_rounded, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              'Semaine précédente',
              style: AppTextStyles.body(color: fg)
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Active session card ──────────────────────────────────────────────────────

class _ActiveSessionCard extends StatelessWidget {
  final CashControlState state;
  final bool isDark;
  const _ActiveSessionCard({required this.state, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final session = state.activeSession!;
    final isOpen = session.status == CashSessionStatus.open;
    final badgeColor = isOpen ? AppColors.deepGreen : AppColors.coolGray;

    return _SessionCardShell(
      isDark: isDark,
      accentColor: badgeColor,
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(session.openedAt),
                  style: AppTextStyles.h3(
                      color:
                          isDark ? AppColors.warmWhite : AppColors.nearBlack),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ouvert à ${_timeStr(session.openedAt)} par ${session.openedBy}',
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: badgeColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: badgeColor, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(
                  isOpen ? 'OUVERT' : 'FERMÉ',
                  style: AppTextStyles.caption(color: badgeColor)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
      rows: [
        _StatRow(
          label: 'Solde d\'ouverture',
          htg: session.openingBalanceHtg,
          usd: session.openingBalanceUsd,
          isDark: isDark,
        ),
        _StatRow(
          label: 'Entrée de caisse',
          htg: state.totalIn,
          usd: state.totalInUsd,
          isDark: isDark,
          color: AppColors.deepGreen,
          sign: '+',
        ),
        _StatRow(
          label: 'Sortie de caisse',
          htg: state.totalOut,
          usd: state.totalOutUsd,
          isDark: isDark,
          color: AppColors.boldRed,
          sign: '-',
        ),
        _StatRow(
          label: 'Solde attendu',
          htg: state.expectedBalance,
          usd: state.expectedBalanceUsd,
          isDark: isDark,
          isBold: true,
          color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
        ),
      ],
    );
  }
}

// ─── Closed session card ──────────────────────────────────────────────────────

class _ClosedSessionCard extends StatelessWidget {
  final SessionSummary summary;
  final bool isDark;
  const _ClosedSessionCard(
      {required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final balanced = summary.isBalanced;
    final balanceColor =
        balanced ? AppColors.deepGreen : AppColors.boldRed;

    return _SessionCardShell(
      isDark: isDark,
      accentColor: balanceColor,
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(session.openedAt),
                  style: AppTextStyles.h3(
                      color: isDark
                          ? AppColors.warmWhite
                          : AppColors.nearBlack),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_timeStr(session.openedAt)} – ${_timeStr(session.closedAt!)}  ·  Fermé par ${summary.closedBy}',
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: balanceColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: balanceColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              balanced ? 'BALANCED' : 'SHORT',
              style: AppTextStyles.caption(color: balanceColor)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      rows: [
        _StatRow(
          label: 'Solde d\'ouverture',
          htg: session.openingBalanceHtg,
          usd: session.openingBalanceUsd,
          isDark: isDark,
        ),
        _StatRow(
          label: 'Entrée de caisse',
          htg: summary.totalInHtg,
          usd: summary.totalInUsd,
          isDark: isDark,
          color: AppColors.deepGreen,
          sign: '+',
        ),
        _StatRow(
          label: 'Sortie de caisse',
          htg: summary.totalOutHtg,
          usd: summary.totalOutUsd,
          isDark: isDark,
          color: AppColors.boldRed,
          sign: '-',
        ),
        _StatRow(
          label: 'Solde final',
          htg: summary.finalBalanceHtg,
          usd: summary.finalBalanceUsd,
          isDark: isDark,
          isBold: true,
          color: balanceColor,
        ),
        if (!balanced)
          _StatRow(
            label: summary.overShortHtg < 0 ? 'Manque' : 'Excédent',
            htg: summary.overShortHtg.abs(),
            usd: summary.overShortUsd.abs(),
            isDark: isDark,
            color: balanceColor,
            sign: summary.overShortHtg < 0 ? '-' : '+',
          ),
      ],
      note: session.closingNote,
    );
  }
}

// ─── Card shell ───────────────────────────────────────────────────────────────

class _SessionCardShell extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final Widget header;
  final List<Widget> rows;
  final String? note;

  const _SessionCardShell({
    required this.isDark,
    required this.accentColor,
    required this.header,
    required this.rows,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final cardBg = isDark ? const Color(0xFF1A2535) : AppColors.white;

    // Flutter forbids borderRadius with non-uniform border colors, so the
    // left accent bar is drawn as a Positioned child inside a ClipRRect.
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: borderColor),
        boxShadow: isDark ? [] : AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: accentColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ...rows,
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 13,
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            note!,
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat row ─────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final String label;
  final double htg;
  final double usd;
  final bool isDark;
  final bool isBold;
  final Color? color;
  final String sign;

  const _StatRow({
    required this.label,
    required this.htg,
    required this.usd,
    required this.isDark,
    this.isBold = false,
    this.color,
    this.sign = '',
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final valueColor =
        color ?? (isDark ? AppColors.warmWhite : AppColors.nearBlack);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.caption(color: labelColor).copyWith(
                fontWeight:
                    isBold ? FontWeight.w700 : FontWeight.normal),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${CurrencyFormatter.local(context, htg)}',
                style: AppTextStyles.body(color: valueColor).copyWith(
                    fontWeight:
                        isBold ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 12),
              ),
              Text(
                '$sign\$${usd.toStringAsFixed(2)}',
                style: AppTextStyles.caption(
                        color: (color ??
                                (isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray))
                            .withValues(alpha: 0.7))
                    .copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Panel header ─────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool isDark;

  const _PanelHeader({
    required this.title,
    required this.icon,
    required this.isDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkBorder
                : const Color(0xFFEEEEEE),
          ),
        ),
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
            child: Icon(icon, color: AppColors.amber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack)),
                if (subtitle != null)
                  Text(subtitle!, style: AppTextStyles.caption()),
              ],
            ),
          ),
          AppCloseButton(onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _timeStr(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

// e.g. "Mon 24 Feb"
String _shortDate(DateTime dt) {
  const weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];
  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
}

String _dateLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Aujourd\'hui';
  if (diff == 1) return 'Hier';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

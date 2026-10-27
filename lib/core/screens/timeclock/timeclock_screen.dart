import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../printing/pdf_theme.dart';
import '../../models/staff_directory_entry.dart';
import '../../models/timeclock_entry.dart';
import '../../providers/staff_directory_provider.dart';
import '../../providers/staff_session_provider.dart';
import '../../providers/timeclock_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header.dart';
import '../../widgets/app_close_button.dart';

/// Defers overlay / route work until after the current frame and microtask queue,
/// so it does not run during Flutter Web's mouse/pointer device-update phase
/// (avoids `!_debugDuringDeviceUpdate` in [MouseTracker]).
Future<void> _waitUntilAfterPointerPhase() {
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.microtask(() {
      if (!completer.isCompleted) completer.complete();
    });
  });
  return completer.future;
}

// ─────────────────────────────────────────────────────────────────────────────
// TimeclockScreen
// ─────────────────────────────────────────────────────────────────────────────

class TimeclockScreen extends ConsumerStatefulWidget {
  const TimeclockScreen({super.key});

  @override
  ConsumerState<TimeclockScreen> createState() => _TimeclockScreenState();
}

class _TimeclockScreenState extends ConsumerState<TimeclockScreen> {
  TimeclockPeriod _period = TimeclockPeriod.week;
  DateTime? _customStart;
  DateTime? _customEnd;

  (DateTime, DateTime) get _range {
    if (_customStart != null && _customEnd != null) {
      return (_customStart!, _customEnd!);
    }
    return periodRange(_period);
  }

  String? get _customLabel {
    if (_customStart == null || _customEnd == null) return null;
    final f = DateFormat('MMM d');
    return '${f.format(_customStart!)} – ${f.format(_customEnd!)}';
  }

  bool get _isAdmin {
    final role = ref.read(staffSessionProvider)?.role;
    return role == StaffRole.admin ||
        role == StaffRole.manager ||
        role == StaffRole.owner;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = ref.watch(timeclockProvider);
    final directory = ref.watch(staffDirectoryProvider);
    final active = directory.where((e) => e.isActive).toList();
    final (start, end) = _range;
    final isAdmin = _isAdmin;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Pointage',
                    subtitle: 'Suivre les heures et la présence',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _PeriodBar(
                          period: _period,
                          customLabel: _customLabel,
                          isDark: isDark,
                          onPeriod: (p) => setState(() {
                            _period = p;
                            _customStart = null;
                            _customEnd = null;
                          }),
                          onCustomRange: _pickCustomRange,
                          onClearCustom: () => setState(() {
                            _customStart = null;
                            _customEnd = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MonthlyHoursPdfControl(isDark: isDark),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Employee tiles ─────────────────────────────────────────────
          if (active.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('Aucun employé actif.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: active.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final emp = active[i];
                  final empEntries = entries
                      .where((e) =>
                          e.employeeId == emp.id &&
                          !e.clockIn.isBefore(start) &&
                          !e.clockIn.isAfter(end))
                      .toList()
                    ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
                  final isClockedIn =
                      entries.any((e) => e.employeeId == emp.id && e.isOpen);

                  return _EmployeeTile(
                    key: ValueKey(emp.id),
                    employeeId: emp.id,
                    name: emp.fullName,
                    role: emp.role,
                    entries: empEntries,
                    start: start,
                    end: end,
                    isClockedIn: isClockedIn,
                    isAdmin: isAdmin,
                    isDark: isDark,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customStart ?? now.subtract(const Duration(days: 13)),
        end: _customEnd ?? now,
      ),
      helpText: 'Choisir la période',
      saveText: 'Appliquer le filtre',
      fieldStartLabelText: 'Date de début',
      fieldEndLabelText: 'Date de fin',
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
        final stripBg = isDark
            ? AppColors.darkSurface
            : const Color(0xFFEDF3FF);
        final stripFg = isDark ? AppColors.coolGray : AppColors.darkGray;

        // The picker child is a full-screen Scaffold — it must fill the
        // remaining space. Using mainAxisSize.max + Expanded avoids overflow.
        return Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Instruction banner ──────────────────────────────────────────
            Material(
              color: stripBg,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.info_outline_rounded, color: accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Comment choisir une période',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final (num, text) in [
                            (1, 'Touchez la date de début sur le calendrier.'),
                            (2, 'Touchez la date de fin.'),
                            (3, 'Touchez Appliquer le filtre pour valider la période.'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$num.  ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: accent.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      text,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                        color: stripFg,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isDark)
              Divider(height: 1, thickness: 1, color: AppColors.darkBorder)
            else
              Divider(height: 1, thickness: 1, color: const Color(0xFFD0DAEA)),
            // ── Full-screen picker ──────────────────────────────────────────
            if (child != null) Expanded(child: child),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _customStart = picked.start;
        _customEnd = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Period bar — pill segmented-style chips
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodBar extends StatelessWidget {
  final TimeclockPeriod period;
  final String? customLabel;
  final bool isDark;
  final void Function(TimeclockPeriod) onPeriod;
  final VoidCallback onCustomRange;
  final VoidCallback onClearCustom;

  const _PeriodBar({
    required this.period,
    required this.customLabel,
    required this.isDark,
    required this.onPeriod,
    required this.onCustomRange,
    required this.onClearCustom,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap all chips in a subtle pill-shaped container
    final trackBg = isDark ? const Color(0xFF1E2A3A) : const Color(0xFFEAEDF2);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(32),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...TimeclockPeriod.values.map((p) {
              final sel = customLabel == null && period == p;
              return _Chip(
                label: timeclockPeriodLabel(p),
                selected: sel,
                isDark: isDark,
                onTap: () => onPeriod(p),
              );
            }),
            _Chip(
              label: customLabel ?? 'Custom',
              selected: customLabel != null,
              isDark: isDark,
              onTap: onCustomRange,
              icon: Icons.date_range_rounded,
            ),
            if (customLabel != null) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: 'Effacer la période',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onClearCustom,
                    customBorder: const CircleBorder(),
                    splashFactory: NoSplash.splashFactory,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: isDark
                              ? const Color(0xFF9AAABF)
                              : const Color(0xFF5A6A7E),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBg = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final fg = selected
        ? Colors.white
        : (isDark ? const Color(0xFF9AAABF) : const Color(0xFF5A6A7E));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: selected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: selectedBg.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          overlayColor: selected
              ? Colors.white.withValues(alpha: 0.1)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monthly hours PDF — pick month (current year), download summary
// ─────────────────────────────────────────────────────────────────────────────

class _MonthPickerDialog extends StatelessWidget {
  final int year;
  final bool isDark;

  const _MonthPickerDialog({
    required this.year,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_outlined, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Heures du mois (PDF)',
                          style: AppTextStyles.h2(color: textColor),
                        ),
                        Text(
                          'Year $year · totals per employee',
                          style: AppTextStyles.caption(color: labelColor),
                        ),
                      ],
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 360,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: 12,
                itemBuilder: (_, i) {
                  final m = i + 1;
                  final label =
                      DateFormat.yMMMM().format(DateTime(year, m));
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    title: Text(
                      label,
                      style: AppTextStyles.body(color: textColor),
                    ),
                    trailing: Icon(Icons.download_outlined,
                        size: 18, color: accent),
                    onTap: () => Navigator.pop(context, m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyHoursPdfControl extends ConsumerStatefulWidget {
  final bool isDark;

  const _MonthlyHoursPdfControl({required this.isDark});

  @override
  ConsumerState<_MonthlyHoursPdfControl> createState() =>
      _MonthlyHoursPdfControlState();
}

class _MonthlyHoursPdfControlState extends ConsumerState<_MonthlyHoursPdfControl> {
  bool _busy = false;

  Future<void> _openPickerAndDownload() async {
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final year = DateTime.now().year;
    final month = await showDialog<int>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _MonthPickerDialog(year: year, isDark: widget.isDark),
    );
    if (month == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final entries = ref.read(timeclockProvider);
      final directory = ref.read(staffDirectoryProvider);
      final active = directory.where((e) => e.isActive).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

      final bytes = await _buildMonthlyHoursSummaryPdf(
        year: year,
        month: month,
        allEntries: entries,
        staffActiveSorted: active,
      );
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'monthly_hours_${year}_${month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e, _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Impossible de créer le PDF : $e'
                  : 'Impossible de créer le PDF. Veuillez réessayer.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final trackFg =
        widget.isDark ? const Color(0xFF9AAABF) : const Color(0xFF5A6A7E);

    return Tooltip(
      message: 'Télécharger le résumé mensuel des heures (PDF)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : _openPickerAndDownload,
          borderRadius: BorderRadius.circular(28),
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined,
                          size: 16, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'PDF mensuel',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: trackFg,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Employee tile (ExpansionTile — safe in scroll views)
// ─────────────────────────────────────────────────────────────────────────────

class _EmployeeTile extends StatelessWidget {
  final String employeeId;
  final String name;
  final StaffRole role;
  final List<TimeclockEntry> entries;
  final DateTime start;
  final DateTime end;
  final bool isClockedIn;
  final bool isAdmin;
  final bool isDark;

  const _EmployeeTile({
    super.key,
    required this.employeeId,
    required this.name,
    required this.role,
    required this.entries,
    required this.start,
    required this.end,
    required this.isClockedIn,
    required this.isAdmin,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.white;
    final total = totalDuration(entries);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            backgroundColor: cardBg,
            collapsedBackgroundColor: cardBg,
            iconColor: isDark ? AppColors.coolGray : AppColors.darkGray,
            collapsedIconColor:
                isDark ? AppColors.coolGray : AppColors.darkGray,
            title: Row(
              children: [
                // Avatar with clocked-in dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          AppColors.primaryBlue.withValues(alpha: 0.1),
                      child: Text(
                        name[0].toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    if (isClockedIn)
                      Positioned(
                        bottom: -1,
                        right: -1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.deepGreen,
                            border: Border.all(color: cardBg, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Name + role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Text(
                            staffRoleDisplayLabel(role),
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                          if (isClockedIn) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.deepGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'En service',
                                style: AppTextStyles.caption(
                                        color: AppColors.deepGreen)
                                    .copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Total hours
                Text(
                  formatDuration(total),
                  style: AppTextStyles.price(color: accent),
                ),
                const SizedBox(width: 4),
              ],
            ),
            children: [
              _TileDetail(
                employeeId: employeeId,
                entries: entries,
                start: start,
                end: end,
                total: total,
                employeeName: name,
                role: role,
                isAdmin: isAdmin,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile detail  — plain Column, zero interactive non-button widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TileDetail extends StatelessWidget {
  final String employeeId;
  final List<TimeclockEntry> entries;
  final DateTime start;
  final DateTime end;
  final Duration total;
  final String employeeName;
  final StaffRole role;
  final bool isAdmin;
  final bool isDark;

  const _TileDetail({
    required this.employeeId,
    required this.entries,
    required this.start,
    required this.end,
    required this.total,
    required this.employeeName,
    required this.role,
    required this.isAdmin,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final divColor = isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final days = _buildDays();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: divColor),

        _ExpandedTimesheetToolbar(
          employeeId: employeeId,
          employeeName: employeeName,
          role: role,
          entries: entries,
          periodStart: start,
          periodEnd: end,
          isAdmin: isAdmin,
          isDark: isDark,
        ),

        // Column headers
        Padding(
          padding: EdgeInsets.fromLTRB(16, 10, isAdmin ? 60 : 16, 6),
          child: Row(children: [
            _hdr('Date', 3, labelColor),
            _hdr('Pointer l\'arrivée', 2, labelColor),
            _hdr('Pointer le départ', 2, labelColor),
            _hdr('Heures', 2, labelColor),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: divColor),

        // Data rows
        for (final day in days) ...[
          if (day.entries.isEmpty)
            _DataRow(
              date: day.date,
              entry: null,
              showDate: true,
              isAdmin: isAdmin,
              isDark: isDark,
            )
          else
            for (var j = 0; j < day.entries.length; j++)
              _DataRow(
                date: day.date,
                entry: day.entries[j],
                showDate: j == 0,
                isAdmin: isAdmin,
                isDark: isDark,
              ),
          Divider(height: 1, thickness: 1, color: divColor),
        ],

        // Footer — total only (print/download live in top toolbar)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              Text('Total  ',
                  style: AppTextStyles.caption(color: labelColor)
                      .copyWith(fontWeight: FontWeight.w600)),
              Text(formatDuration(total),
                  style: AppTextStyles.price(color: accent)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hdr(String label, int flex, Color color) => Expanded(
        flex: flex,
        child: Text(label,
            style: AppTextStyles.caption(color: color)
                .copyWith(fontWeight: FontWeight.w600)),
      );

  List<_Day> _buildDays() {
    final out = <_Day>[];
    var cur = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cur.isAfter(last)) {
      final dayEntries = entries
          .where((e) =>
              e.clockIn.year == cur.year &&
              e.clockIn.month == cur.month &&
              e.clockIn.day == cur.day)
          .toList()
        ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
      out.add(_Day(cur, dayEntries));
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }
}

class _Day {
  final DateTime date;
  final List<TimeclockEntry> entries;
  const _Day(this.date, this.entries);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data row — pure display + optional admin edit button
// ─────────────────────────────────────────────────────────────────────────────

class _DataRow extends ConsumerStatefulWidget {
  final DateTime date;
  final TimeclockEntry? entry;
  final bool showDate;
  final bool isAdmin;
  final bool isDark;

  const _DataRow({
    required this.date,
    required this.entry,
    required this.showDate,
    required this.isAdmin,
    required this.isDark,
  });

  @override
  ConsumerState<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends ConsumerState<_DataRow> {
  bool _editing = false;
  DateTime? _draftClockIn;
  DateTime? _draftClockOut;

  @override
  void initState() {
    super.initState();
    _hydrateDrafts();
  }

  @override
  void didUpdateWidget(covariant _DataRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.entry?.id != widget.entry?.id) {
      _hydrateDrafts();
    }
  }

  void _hydrateDrafts() {
    _draftClockIn = widget.entry?.clockIn;
    _draftClockOut = widget.entry?.clockOut;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
    final accent = widget.isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final labelColor = widget.isDark ? AppColors.coolGray : AppColors.darkGray;
    final textColor = widget.isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final dayFmt = DateFormat('EEE, MMM d');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: isToday && widget.showDate
              ? accent.withValues(alpha: 0.05)
              : null,
          padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
          child: Row(
            children: [
              // Date col
              Expanded(
                flex: 3,
                child: widget.showDate
                    ? Row(
                        children: [
                          if (isToday)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Aujourd\'hui',
                                  style: AppTextStyles.caption(color: accent)
                                      .copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10)),
                            ),
                          Expanded(
                            child: Text(
                              dayFmt.format(widget.date),
                              style: AppTextStyles.body(color: textColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(),
              ),

              // Clock-in col
              Expanded(
                flex: 2,
                child: widget.entry == null
                    ? Text('—', style: AppTextStyles.body(color: labelColor))
                    : _TimeCell(
                        current: widget.entry!.clockIn,
                        original: widget.entry!.originalClockIn,
                        isDark: widget.isDark,
                      ),
              ),

              // Clock-out col
              Expanded(
                flex: 2,
                child: widget.entry == null
                    ? Text('—', style: AppTextStyles.body(color: labelColor))
                    : (widget.entry!.isOpen
                        ? Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.deepGreen,
                                ),
                              ),
                              Text('En cours',
                                  style: AppTextStyles.caption(
                                          color: AppColors.deepGreen)
                                      .copyWith(fontWeight: FontWeight.w600)),
                            ],
                          )
                        : _TimeCell(
                            current: widget.entry!.clockOut!,
                            original: widget.entry!.originalClockOut,
                            isDark: widget.isDark,
                          )),
              ),

              // Hours col
              Expanded(
                flex: 2,
                child: Text(
                  widget.entry?.durationLabel ?? '—',
                  style: AppTextStyles.body(
                          color: widget.entry != null ? textColor : labelColor)
                      .copyWith(
                          fontWeight: widget.entry != null
                              ? FontWeight.w600
                              : FontWeight.w400),
                ),
              ),

              if (widget.isAdmin && widget.entry != null)
                SizedBox(
                  width: 60,
                  child: TextButton(
                    onPressed: _toggleEdit,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      minimumSize: const Size(40, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      _editing ? 'Fermer' : 'Modifier',
                      style: AppTextStyles.caption(color: accent)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              else if (widget.isAdmin)
                const SizedBox(width: 60),
            ],
          ),
        ),
        if (widget.entry?.isManual == true &&
            (widget.entry!.manualEnteredByName ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.deepGreen.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Manual · ${widget.entry!.manualEnteredByName}',
                  style: AppTextStyles.caption(color: AppColors.deepGreen)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 10),
                ),
              ),
            ),
          ),
        if (_editing && widget.entry != null)
          _InlineEditor(
            isDark: widget.isDark,
            draftClockIn: _draftClockIn!,
            draftClockOut: _draftClockOut,
            isOpenShift: widget.entry!.isOpen,
            onPickClockIn: _pickClockIn,
            onPickClockOut: _pickClockOut,
            onCancel: _cancelEdit,
            onSave: _saveEdit,
          ),
      ],
    );
  }

  void _toggleEdit() {
    setState(() {
      if (!_editing) {
        _hydrateDrafts();
      }
      _editing = !_editing;
    });
  }

  void _cancelEdit() {
    setState(() {
      _hydrateDrafts();
      _editing = false;
    });
  }

  Future<void> _pickClockIn() async {
    if (_draftClockIn == null) return;
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_draftClockIn!),
      helpText: 'Choisir l\'heure d\'arrivée',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final base = _draftClockIn!;
      _draftClockIn =
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
    });
  }

  Future<void> _pickClockOut() async {
    if (_draftClockOut == null) return;
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_draftClockOut!),
      helpText: 'Choisir l\'heure de départ',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final base = _draftClockOut!;
      _draftClockOut =
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
    });
  }

  void _saveEdit() {
    final entry = widget.entry;
    if (entry == null) return;
    final session = ref.read(staffSessionProvider);
    final err = ref.read(timeclockProvider.notifier).editEntry(
          entry.id,
          newClockIn: _draftClockIn != entry.clockIn ? _draftClockIn : null,
          newClockOut: _draftClockOut != entry.clockOut ? _draftClockOut : null,
          enteredByName: session?.employeeName ?? 'Admin',
          enteredById: session?.employeeId,
        );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _editing = false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top toolbar: Add shift (admin) + Download PDF + Print — right-aligned
// ─────────────────────────────────────────────────────────────────────────────

String _safeTimesheetFileBase(String employeeName) {
  final raw = employeeName
      .trim()
      .replaceAll(RegExp(r'[^\w\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return raw.isEmpty ? 'timesheet' : raw;
}

Future<Uint8List> _buildTimesheetPdfBytes({
  required String employeeName,
  required List<TimeclockEntry> entries,
  required DateTime periodStart,
  required DateTime periodEnd,
}) async {
  final sorted = List<TimeclockEntry>.from(entries)
    ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
  final total = totalDuration(sorted);
  final timeFmt = DateFormat('h:mm a');
  final dayFmt = DateFormat('EEE MMM d, yyyy');
  final rangeFmt = DateFormat('MMM d, yyyy');

  pw.TableRow headerRow() => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _pdfCell('Date', bold: true),
          _pdfCell('Arrivée', bold: true),
          _pdfCell('Départ', bold: true),
          _pdfCell('Heures', bold: true, align: pw.TextAlign.right),
        ],
      );

  pw.TableRow dataRow(TimeclockEntry e) => pw.TableRow(
        children: [
          _pdfCell(dayFmt.format(e.clockIn)),
          _pdfCell(timeFmt.format(e.clockIn)),
          _pdfCell(
            e.clockOut != null ? timeFmt.format(e.clockOut!) : 'Ouvert',
          ),
          _pdfCell(e.durationLabel, align: pw.TextAlign.right),
        ],
      );

  pw.TableRow emptyRow() => pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: pw.Text(
              'Aucun quart sur cette période.',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
          _pdfCell(''),
          _pdfCell(''),
          _pdfCell(''),
        ],
      );

  final theme = await shopPdfTheme();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => [
        pw.Text(
          'FEUILLE DE TEMPS',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: PdfColors.grey600),
        pw.SizedBox(height: 6),
        pw.Text(
          employeeName,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Period: ${rangeFmt.format(periodStart)} – ${rangeFmt.format(periodEnd)}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(1.8),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FlexColumnWidth(1.2),
          },
          children: [
            headerRow(),
            if (sorted.isEmpty) emptyRow() else ...sorted.map(dataRow),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Total : ${formatDuration(total)}',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Generated ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _pdfCell(
  String text, {
  bool bold = false,
  pw.TextAlign align = pw.TextAlign.left,
}) {
  final style = pw.TextStyle(
    fontSize: 9,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(text, style: style, textAlign: align),
  );
}

(DateTime, DateTime) _monthBounds(int year, int month) {
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 0, 23, 59, 59);
  return (start, end);
}

/// One row per active employee: total hours in [year]/[month] only (no shift detail).
Future<Uint8List> _buildMonthlyHoursSummaryPdf({
  required int year,
  required int month,
  required List<TimeclockEntry> allEntries,
  required List<StaffDirectoryEntry> staffActiveSorted,
}) async {
  final (rangeStart, rangeEnd) = _monthBounds(year, month);
  final monthTitle = DateFormat.yMMMM().format(DateTime(year, month));
  final rangeLabel =
      '${DateFormat.yMMMd().format(rangeStart)} – ${DateFormat.yMMMd().format(rangeEnd)}';

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _pdfCell('Employee', bold: true),
        _pdfCell('Role', bold: true),
        _pdfCell('Heures totales', bold: true, align: pw.TextAlign.right),
      ],
    ),
  ];

  Duration grandTotal = Duration.zero;
  for (final emp in staffActiveSorted) {
    final inMonth = allEntries.where((e) {
      if (e.employeeId != emp.id) return false;
      return !e.clockIn.isBefore(rangeStart) && !e.clockIn.isAfter(rangeEnd);
    }).toList();
    final total = totalDuration(inMonth);
    grandTotal += total;
    rows.add(
      pw.TableRow(
        children: [
          _pdfCell(emp.fullName),
          _pdfCell(staffRoleDisplayLabel(emp.role)),
          _pdfCell(formatDuration(total), align: pw.TextAlign.right),
        ],
      ),
    );
  }

  final theme = await shopPdfTheme();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => [
        pw.Text(
          'RÉSUMÉ DES HEURES',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: PdfColors.grey600),
        pw.SizedBox(height: 4),
        pw.Text(
          monthTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Period covered: $rangeLabel',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Totaux par employé seulement — pas le détail des quarts.',
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey700,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.6),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.2),
          },
          children: rows,
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Personnel actif : ${staffActiveSorted.length} · Heures cumulées : ${formatDuration(grandTotal)}',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Generated ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

class _ExpandedTimesheetToolbar extends ConsumerStatefulWidget {
  final String employeeId;
  final String employeeName;
  final StaffRole role;
  final List<TimeclockEntry> entries;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool isAdmin;
  final bool isDark;

  const _ExpandedTimesheetToolbar({
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.entries,
    required this.periodStart,
    required this.periodEnd,
    required this.isAdmin,
    required this.isDark,
  });

  @override
  ConsumerState<_ExpandedTimesheetToolbar> createState() =>
      _ExpandedTimesheetToolbarState();
}

class _ExpandedTimesheetToolbarState extends ConsumerState<_ExpandedTimesheetToolbar> {
  bool _busyDownload = false;

  Future<void> _downloadPdf() async {
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    setState(() => _busyDownload = true);
    try {
      final bytes = await _buildTimesheetPdfBytes(
        employeeName: widget.employeeName,
        entries: widget.entries,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
      );
      if (!mounted) return;
      final base = _safeTimesheetFileBase(widget.employeeName);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${base}_timesheet.pdf',
      );
    } catch (e, _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Impossible de créer le PDF : $e'
                  : 'Impossible de créer le PDF. Veuillez réessayer.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDownload = false);
    }
  }

  Future<void> _openPrintDialog() async {
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _PrintDialog(
        employeeName: widget.employeeName,
        entries: widget.entries,
        defaultStart: widget.periodStart,
        defaultEnd: widget.periodEnd,
        isDark: widget.isDark,
      ),
    );
  }

  Future<void> _openAddShiftModal() async {
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AddShiftModalDialog(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        role: widget.role,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
        isDark: widget.isDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final amber = AppColors.amber;
    final panelBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.45)
        : const Color(0xFFF3F6FB);
    final borderColor = isDark
        ? AppColors.darkBorder.withValues(alpha: 0.85)
        : const Color(0xFFE2E8F0);

    ButtonStyle outlineActionStyle({bool primaryAccent = false}) =>
        OutlinedButton.styleFrom(
          foregroundColor: primaryAccent ? amber : accent,
          side: BorderSide(
            color: (primaryAccent ? amber : accent).withValues(alpha: 0.55),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          splashFactory: NoSplash.splashFactory,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  final printLabel = compact ? 'Imprimer' : 'Imprimer la feuille de temps';

                  Widget addBtn() => Tooltip(
                        message: 'Ajouter un quart manuel',
                        child: OutlinedButton.icon(
                          onPressed: _openAddShiftModal,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Ajouter un quart',
                            style: GoogleFonts.poppins(
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: outlineActionStyle(primaryAccent: true),
                        ),
                      );

                  Widget downloadBtn() => Tooltip(
                        message: 'Télécharger la feuille de temps en PDF',
                        child: OutlinedButton.icon(
                          onPressed:
                              _busyDownload ? null : () => _downloadPdf(),
                          icon: _busyDownload
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accent,
                                  ),
                                )
                              : Icon(Icons.download_outlined, size: 18),
                          label: Text(
                            'Télécharger',
                            style: GoogleFonts.poppins(
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: outlineActionStyle(),
                        ),
                      );

                  Widget printBtn() => Tooltip(
                        message: 'Aperçu de la période et impression',
                        child: OutlinedButton.icon(
                          onPressed: () => _openPrintDialog(),
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: Text(
                            printLabel,
                            style: GoogleFonts.poppins(
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: outlineActionStyle(),
                        ),
                      );

                  return Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.isAdmin) addBtn(),
                        downloadBtn(),
                        printBtn(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add shift — compact modal
// ─────────────────────────────────────────────────────────────────────────────

class _AddShiftModalDialog extends ConsumerStatefulWidget {
  final String employeeId;
  final String employeeName;
  final StaffRole role;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool isDark;

  const _AddShiftModalDialog({
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.periodStart,
    required this.periodEnd,
    required this.isDark,
  });

  @override
  ConsumerState<_AddShiftModalDialog> createState() =>
      _AddShiftModalDialogState();
}

class _AddShiftModalDialogState extends ConsumerState<_AddShiftModalDialog> {
  late DateTime _day;
  TimeOfDay? _timeIn;   // null = not yet picked
  TimeOfDay? _timeOut;  // null = not yet picked

  // Inline alert shown inside the modal instead of SnackBars
  String? _alertMessage;
  bool _alertIsError = true; // false = warning (amber)

  DateTime get _firstDate => DateTime(
        widget.periodStart.year,
        widget.periodStart.month,
        widget.periodStart.day,
      );

  DateTime get _lastDate => DateTime(
        widget.periodEnd.year,
        widget.periodEnd.month,
        widget.periodEnd.day,
      );

  @override
  void initState() {
    super.initState();
    _resetDefaults();
  }

  void _resetDefaults() {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    if (d.isBefore(_firstDate)) d = _firstDate;
    if (d.isAfter(_lastDate)) d = _lastDate;
    _day = d;
    _timeIn = null;
    _timeOut = null;
    _alertMessage = null;
  }

  void _clearAlert() {
    if (_alertMessage != null) setState(() => _alertMessage = null);
  }

  void _showAlert(String message, {bool isError = true}) {
    setState(() {
      _alertMessage = message;
      _alertIsError = isError;
    });
  }

  Future<void> _pickDate() async {
    _clearAlert();
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = picked);
  }

  Future<void> _pickIn() async {
    _clearAlert();
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeIn ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Arrivée',
    );
    if (picked == null || !mounted) return;
    setState(() => _timeIn = picked);
  }

  Future<void> _pickOut() async {
    _clearAlert();
    await _waitUntilAfterPointerPhase();
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOut ?? const TimeOfDay(hour: 16, minute: 0),
      helpText: 'Départ',
    );
    if (picked == null || !mounted) return;
    setState(() => _timeOut = picked);
  }

  DateTime _toDateTime(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  void _save() {
    if (_timeIn == null || _timeOut == null) {
      _showAlert(
        'Indiquez l\'heure d\'arrivée et l\'heure de départ.',
        isError: false,
      );
      return;
    }
    final clockIn = _toDateTime(_timeIn!);
    final clockOut = _toDateTime(_timeOut!);
    if (!clockOut.isAfter(clockIn)) {
      _showAlert(
        'Le départ doit être après l\'arrivée.',
        isError: true,
      );
      return;
    }
    final session = ref.read(staffSessionProvider);
    final err = ref.read(timeclockProvider.notifier).addManualShift(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          role: widget.role,
          clockIn: clockIn,
          clockOut: clockOut,
          enteredByName: session?.employeeName ?? 'Admin',
          enteredById: session?.employeeId,
        );
    if (!mounted) return;
    if (err != null) {
      _showAlert(err, isError: true);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Vacation ajoutée pour ${widget.employeeName}'),
        backgroundColor: AppColors.deepGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final surfaceBg = isDark ? AppColors.darkSurface : AppColors.white;
    final rowBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.55)
        : const Color(0xFFF5F7FB);
    final rowBorder = isDark
        ? AppColors.darkBorder
        : const Color(0xFFE4EAF2);

    final timeFmt = DateFormat('h:mm a');
    final dateFmt = DateFormat('EEE, MMM d, yyyy');

    Widget pickerRow({
      required IconData icon,
      required Color iconBg,
      required Color iconFg,
      required String label,
      required String? value, // null = not yet picked
      required VoidCallback onTap,
    }) {
      final hasValue = value != null;
      return Material(
        color: rowBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashFactory: NoSplash.splashFactory,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: rowBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: hasValue ? iconBg : iconBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 17,
                      color: hasValue ? iconFg : iconFg.withValues(alpha: 0.5)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        hasValue ? value : 'Touchez pour régler l\'heure',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight:
                              hasValue ? FontWeight.w600 : FontWeight.w400,
                          color: hasValue ? textColor : labelColor,
                          fontStyle: hasValue
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: labelColor),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: surfaceBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Colored header ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF1A3250),
                          const Color(0xFF0F1923),
                        ]
                      : [
                          AppColors.primaryBlue,
                          const Color(0xFF2563EB),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.schedule_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ajouter un quart',
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 13,
                                color: Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.employeeName,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────────
            SingleChildScrollView(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pickerRow(
                      icon: Icons.calendar_today_outlined,
                      iconBg: accent.withValues(alpha: 0.12),
                      iconFg: accent,
                      label: 'DATE',
                      value: dateFmt.format(_day),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 8),
                    pickerRow(
                      icon: Icons.login_rounded,
                      iconBg: AppColors.deepGreen.withValues(alpha: 0.12),
                      iconFg: AppColors.deepGreen,
                      label: 'ARRIVÉE',
                      value: _timeIn != null
                          ? timeFmt.format(_toDateTime(_timeIn!))
                          : null,
                      onTap: _pickIn,
                    ),
                    const SizedBox(height: 8),
                    pickerRow(
                      icon: Icons.logout_rounded,
                      iconBg: AppColors.boldRed.withValues(alpha: 0.10),
                      iconFg: isDark
                          ? AppColors.coralRed
                          : AppColors.boldRed,
                      label: 'DÉPART',
                      value: _timeOut != null
                          ? timeFmt.format(_toDateTime(_timeOut!))
                          : null,
                      onTap: _pickOut,
                    ),

                    // Duration badge — shown only once both times are set
                    if (_timeIn != null && _timeOut != null) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (context) {
                        final dur = _toDateTime(_timeOut!)
                            .difference(_toDateTime(_timeIn!));
                        final valid = dur.inMinutes > 0;
                        final label = valid
                            ? '${dur.inHours}h '
                              '${(dur.inMinutes % 60).toString().padLeft(2, '0')}m'
                            : 'Période invalide';
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: valid
                                ? accent.withValues(alpha: 0.08)
                                : AppColors.boldRed.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: valid
                                  ? accent.withValues(alpha: 0.3)
                                  : AppColors.boldRed.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timelapse_rounded,
                                  size: 16,
                                  color: valid ? accent : AppColors.boldRed),
                              const SizedBox(width: 8),
                              Text(
                                'Durée du quart',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: labelColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                label,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: valid ? accent : AppColors.boldRed,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            // ── Inline alert ───────────────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _alertMessage != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _alertIsError
                              ? AppColors.boldRed.withValues(alpha: 0.10)
                              : AppColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _alertIsError
                                ? AppColors.boldRed.withValues(alpha: 0.40)
                                : AppColors.amber.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _alertIsError
                                  ? Icons.error_outline_rounded
                                  : Icons.warning_amber_rounded,
                              size: 18,
                              color: _alertIsError
                                  ? (widget.isDark
                                      ? AppColors.coralRed
                                      : AppColors.boldRed)
                                  : AppColors.amber,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _alertMessage!,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _alertIsError
                                      ? (widget.isDark
                                          ? AppColors.coralRed
                                          : AppColors.boldRed)
                                      : (widget.isDark
                                          ? AppColors.amber
                                          : const Color(0xFF7A4F00)),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _clearAlert,
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: _alertIsError
                                    ? (widget.isDark
                                        ? AppColors.coralRed
                                        : AppColors.boldRed)
                                    : AppColors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Footer ─────────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: labelColor,
                        side: BorderSide(color: rowBorder),
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                      child: Text(
                        'Annuler',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        'Enregistrer le quart',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Time cell — shows original (strikethrough) + new (green) when edited
// ─────────────────────────────────────────────────────────────────────────────

class _TimeCell extends StatelessWidget {
  final DateTime current;
  final DateTime? original;
  final bool isDark;

  const _TimeCell({
    required this.current,
    required this.original,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final wasEdited = original != null;

    if (!wasEdited) {
      return Text(timeFmt.format(current),
          style: AppTextStyles.body(color: textColor));
    }

    // Show original (strikethrough muted) above, then new (green) below
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeFmt.format(original!),
          style: AppTextStyles.caption(
                  color: isDark
                      ? const Color(0xFF5A6A7E)
                      : const Color(0xFFAAAAAA))
              .copyWith(
            decoration: TextDecoration.lineThrough,
            decorationColor:
                isDark ? const Color(0xFF5A6A7E) : const Color(0xFFAAAAAA),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeFmt.format(current),
              style: AppTextStyles.body(color: AppColors.deepGreen)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(Icons.check_circle_rounded,
                size: 12, color: AppColors.deepGreen),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline editor
// ─────────────────────────────────────────────────────────────────────────────

class _InlineEditor extends StatelessWidget {
  final bool isDark;
  final DateTime draftClockIn;
  final DateTime? draftClockOut;
  final bool isOpenShift;
  final VoidCallback onPickClockIn;
  final VoidCallback onPickClockOut;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _InlineEditor({
    required this.isDark,
    required this.draftClockIn,
    required this.draftClockOut,
    required this.isOpenShift,
    required this.onPickClockIn,
    required this.onPickClockOut,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = this.isDark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final timeFmt = DateFormat('h:mm a');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: isDark
          ? AppColors.darkBackground.withValues(alpha: 0.28)
          : const Color(0xFFF7FAFF),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Modifier l\'entrée :',
              style: AppTextStyles.caption(color: labelColor)
                  .copyWith(fontWeight: FontWeight.w600)),
          OutlinedButton.icon(
            onPressed: onPickClockIn,
            icon: const Icon(Icons.login_rounded, size: 15),
            label: Text('In ${timeFmt.format(draftClockIn)}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: textColor,
              side: BorderSide(
                  color:
                      isDark ? AppColors.darkBorder : const Color(0xFFD8DDE6)),
              minimumSize: const Size(40, 34),
            ),
          ),
          if (!isOpenShift && draftClockOut != null)
            OutlinedButton.icon(
              onPressed: onPickClockOut,
              icon: const Icon(Icons.logout_rounded, size: 15),
              label: Text('Out ${timeFmt.format(draftClockOut!)}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFD8DDE6)),
                minimumSize: const Size(40, 34),
              ),
            ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onCancel,
            child: Text('Annuler', style: TextStyle(color: labelColor)),
          ),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.check_rounded, size: 15),
            label: const Text('Enregistrer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(40, 34),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Print dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PrintDialog extends StatefulWidget {
  final String employeeName;
  final List<TimeclockEntry> entries;
  final DateTime defaultStart;
  final DateTime defaultEnd;
  final bool isDark;

  const _PrintDialog({
    required this.employeeName,
    required this.entries,
    required this.defaultStart,
    required this.defaultEnd,
    required this.isDark,
  });

  @override
  State<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends State<_PrintDialog> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.defaultStart;
    _end = widget.defaultEnd;
  }

  List<TimeclockEntry> get _filtered => widget.entries
      .where((e) => !e.clockIn.isBefore(_start) && !e.clockIn.isAfter(_end))
      .toList()
    ..sort((a, b) => a.clockIn.compareTo(b.clockIn));

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final total = totalDuration(_filtered);
    final dateFmt = DateFormat('MMM d, yyyy');
    final timeFmt = DateFormat('h:mm a');
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.print_outlined, color: AppColors.primaryBlue),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Imprimer la feuille de temps',
                        style: AppTextStyles.h2(color: textColor))),
                AppCloseButton(onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 14),
                    label: Text(dateFmt.format(_start)),
                    onPressed: () => _pickStart(context),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('à')),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 14),
                    label: Text(dateFmt.format(_end)),
                    onPressed: () => _pickEnd(context),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(widget.employeeName,
                        style: AppTextStyles.h2(color: textColor))),
                Text('Total : ${formatDuration(total)}',
                    style: AppTextStyles.price(color: accent)),
              ]),
              const SizedBox(height: 8),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  _ph('Date', 3, labelColor),
                  _ph('Pointer l\'arrivée', 2, labelColor),
                  _ph('Pointer le départ', 2, labelColor),
                  _ph('Heures', 2, labelColor),
                ]),
              ),
              Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final e = _filtered[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text(
                                DateFormat('EEE MMM d').format(e.clockIn),
                                style: AppTextStyles.body(color: textColor))),
                        Expanded(
                            flex: 2,
                            child: Text(timeFmt.format(e.clockIn),
                                style: AppTextStyles.body(color: textColor))),
                        Expanded(
                            flex: 2,
                            child: Text(
                                e.clockOut != null
                                    ? timeFmt.format(e.clockOut!)
                                    : 'Ouvert',
                                style: AppTextStyles.body(
                                    color: e.isOpen
                                        ? AppColors.deepGreen
                                        : textColor))),
                        Expanded(
                            flex: 2,
                            child: Text(e.durationLabel,
                                style: AppTextStyles.body(color: textColor)
                                    .copyWith(fontWeight: FontWeight.w600))),
                      ]),
                    );
                  },
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              // Row with max width + end alignment gives buttons infinite width on web;
              // shrink-wrap the row so Material buttons get finite constraints (Flutter 3.22+).
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler')),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _doPrint(context),
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('Imprimer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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

  Widget _ph(String t, int flex, Color c) => Expanded(
        flex: flex,
        child: Text(t,
            style: AppTextStyles.caption(color: c)
                .copyWith(fontWeight: FontWeight.w700)),
      );

  Future<void> _pickStart(BuildContext ctx) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: _start,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: _end,
    );
    if (d != null && mounted) setState(() => _start = d);
  }

  Future<void> _pickEnd(BuildContext ctx) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) {
      setState(() => _end = DateTime(d.year, d.month, d.day, 23, 59, 59));
    }
  }

  Future<void> _doPrint(BuildContext ctx) async {
    final name = widget.employeeName;
    final entries = List<TimeclockEntry>.from(_filtered);
    final start = _start;
    final end = _end;
    Navigator.pop(ctx);
    try {
      await Printing.layoutPdf(
        name: 'feuille-de-temps.pdf',
        onLayout: (_) => _buildTimesheetPdfBytes(
          employeeName: name,
          entries: entries,
          periodStart: start,
          periodEnd: end,
        ),
      );
    } catch (_) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('La feuille de temps n\'a pas pu être préparée.'),
        ),
      );
    }
  }
}

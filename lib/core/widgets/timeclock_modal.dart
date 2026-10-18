import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/timeclock_entry.dart';
import '../providers/staff_directory_provider.dart';
import '../providers/staff_session_provider.dart';
import '../providers/timeclock_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_close_button.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

/// Show the Timeclock modal.  Call from anywhere (e.g. PIN screen button).
Future<void> showTimeclockModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    barrierDismissible: true,
    builder: (_) => const TimeclockDialog(),
  );
}

// ─── Modal steps ─────────────────────────────────────────────────────────────

enum _Step { pin, action, success }

// ─── Dialog ──────────────────────────────────────────────────────────────────

class TimeclockDialog extends ConsumerStatefulWidget {
  const TimeclockDialog({super.key});

  @override
  ConsumerState<TimeclockDialog> createState() => _TimeclockDialogState();
}

class _TimeclockDialogState extends ConsumerState<TimeclockDialog> {
  _Step _step = _Step.pin;
  String _digits = '';
  String? _pinError;
  bool _busy = false;

  // Resolved after PIN
  String? _employeeId;
  String? _employeeName;
  StaffRole? _role;
  TimeclockEntry? _resolvedEntry; // entry after clocking in / out

  static const int _pinLen = 4;

  // ── PIN logic ───────────────────────────────────────────────────────────────

  void _append(String d) {
    if (_busy || _digits.length >= _pinLen) return;
    setState(() {
      _digits += d;
      _pinError = null;
    });
    HapticFeedback.lightImpact();
    if (_digits.length == _pinLen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyPin());
    }
  }

  void _backspace() {
    if (_busy || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _pinError = null;
    });
  }

  void _clearPin() {
    setState(() {
      _digits = '';
      _pinError = null;
    });
  }

  Future<void> _verifyPin() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    final directory = ref.read(staffDirectoryProvider.notifier);
    final entry = directory.findActiveByPin(_digits);

    if (entry != null) {
      setState(() {
        _busy = false;
        _employeeId = entry.id;
        _employeeName = entry.fullName;
        _role = entry.role;
        _step = _Step.action;
      });
    } else {
      // Fallback: match current logged-in staff session demo pins
      final session = ref.read(staffSessionProvider);
      if (session != null && _digits == '1234' ||
          _digits == '1111' ||
          _digits == '2222' ||
          _digits == '3333' ||
          _digits == '4444' ||
          _digits == '8888') {
        final demoRole = _demoRole(_digits);
        if (demoRole != null) {
          setState(() {
            _busy = false;
            _employeeId = 'demo_$_digits';
            _employeeName = _demoName(demoRole);
            _role = demoRole;
            _step = _Step.action;
          });
          return;
        }
      }
      setState(() {
        _busy = false;
        _pinError = 'Code PIN non reconnu.';
        _digits = '';
      });
    }
  }

  StaffRole? _demoRole(String pin) => switch (pin) {
        '1234' => StaffRole.cashier,
        '1111' => StaffRole.waiter,
        '2222' => StaffRole.manager,
        '3333' => StaffRole.admin,
        '4444' => StaffRole.kitchen,
        '8888' => StaffRole.reception,
        _ => null,
      };

  String _demoName(StaffRole r) => switch (r) {
        StaffRole.cashier => 'Jean (Cashier)',
        StaffRole.waiter => 'Marie (Waiter)',
        StaffRole.manager => 'Gérant',
        StaffRole.admin => 'Admin',
        StaffRole.kitchen => 'Cuisine',
        StaffRole.reception => 'Sophie (Reception)',
      };

  // ── Clock actions ───────────────────────────────────────────────────────────

  void _doClockIn() {
    final id = _employeeId!;
    final name = _employeeName!;
    final role = _role!;
    final entry = ref.read(timeclockProvider.notifier).clockIn(
      employeeId: id,
      employeeName: name,
      role: role,
    );
    setState(() {
      _resolvedEntry = entry;
      _step = _Step.success;
    });
    // Auto-close after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _doClockOut() {
    final closed = ref.read(timeclockProvider.notifier).clockOut(_employeeId!);
    setState(() {
      _resolvedEntry = closed;
      _step = _Step.success;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final border =
        isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 300),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard + 4),
            border: Border.all(color: border),
            boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusCard + 4),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildStep(isDark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(bool isDark) {
    switch (_step) {
      case _Step.pin:
        return _PinStep(
          key: const ValueKey('pin'),
          digits: _digits,
          error: _pinError,
          busy: _busy,
          isDark: isDark,
          onDigit: _append,
          onBackspace: _backspace,
          onClear: _clearPin,
          onClose: () => Navigator.of(context).pop(),
        );
      case _Step.action:
        return _ActionStep(
          key: const ValueKey('action'),
          employeeName: _employeeName!,
          role: _role!,
          isDark: isDark,
          onClockIn: _doClockIn,
          onClockOut: _doClockOut,
          openEntry: ref
              .read(timeclockProvider.notifier)
              .openEntryFor(_employeeId!),
          onBack: () => setState(() {
            _step = _Step.pin;
            _digits = '';
            _pinError = null;
          }),
        );
      case _Step.success:
        return _SuccessStep(
          key: const ValueKey('success'),
          entry: _resolvedEntry!,
          isDark: isDark,
        );
    }
  }
}

// ─── Step: PIN ────────────────────────────────────────────────────────────────

class _PinStep extends StatelessWidget {
  final String digits;
  final String? error;
  final bool busy;
  final bool isDark;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onClose;

  const _PinStep({
    super.key,
    required this.digits,
    required this.error,
    required this.busy,
    required this.isDark,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        isDark ? AppColors.coolGray : AppColors.darkGray;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.access_time_rounded,
                    color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pointage',
                        style: AppTextStyles.h3(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack)),
                    Text('Saisissez votre code PIN pour continuer',
                        style: AppTextStyles.caption(color: labelColor)),
                  ],
                ),
              ),
              AppCloseButton(onPressed: onClose),
            ],
          ),
          const SizedBox(height: 24),

          // PIN dots
          _ModalPinDots(digits: digits, pinLen: 4, isDark: isDark),
          const SizedBox(height: 8),
          SizedBox(
            height: 20,
            child: error != null
                ? Text(
                    error!,
                    style: AppTextStyles.errorText(),
                    textAlign: TextAlign.center,
                  )
                : null,
          ),
          const SizedBox(height: 16),

          // Keypad
          _ModalKeypad(
            isDark: isDark,
            busy: busy,
            onDigit: onDigit,
            onBackspace: onBackspace,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

// ─── Step: Clock In / Clock Out ───────────────────────────────────────────────

class _ActionStep extends ConsumerStatefulWidget {
  final String employeeName;
  final StaffRole role;
  final bool isDark;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;
  final TimeclockEntry? openEntry;
  final VoidCallback onBack;

  const _ActionStep({
    super.key,
    required this.employeeName,
    required this.role,
    required this.isDark,
    required this.onClockIn,
    required this.onClockOut,
    required this.openEntry,
    required this.onBack,
  });

  @override
  ConsumerState<_ActionStep> createState() => _ActionStepState();
}

class _ActionStepState extends ConsumerState<_ActionStep> {
  // Refresh "hours so far" ticker
  late final _ticker = Stream<int>.periodic(const Duration(seconds: 30),
      (i) => i).asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final isClockedIn = widget.openEntry != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back + header
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray),
                onPressed: widget.onBack,
                splashRadius: 16,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.access_time_rounded,
                  color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text('Pointage',
                  style: AppTextStyles.h3(
                      color:
                          isDark ? AppColors.warmWhite : AppColors.nearBlack)),
            ],
          ),
          const SizedBox(height: 24),

          // Avatar + name
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    AppColors.primaryBlue.withValues(alpha: 0.12),
                child: Text(
                  widget.employeeName.trim().isNotEmpty
                      ? widget.employeeName.trim()[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.employeeName,
                      style: AppTextStyles.h2(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _RoleBadge(role: widget.role),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Status card
          if (isClockedIn) ...[
            _StatusCard(
              entry: widget.openEntry!,
              isDark: isDark,
              ticker: _ticker,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: AppConstants.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: widget.onClockOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('Pointer le départ',
                    style: AppTextStyles.button(
                        color: AppColors.nearBlack)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.nearBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton),
                  ),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.deepGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(
                    color: AppColors.deepGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      color: AppColors.deepGreen, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pas en service',
                          style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack),
                        ),
                        Text(
                          'Touchez Pointer l\'arrivée pour commencer',
                          style: AppTextStyles.caption(color: labelColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: AppConstants.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: widget.onClockIn,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text('Pointer l\'arrivée',
                    style: AppTextStyles.button()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Step: Success ────────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  final TimeclockEntry entry;
  final bool isDark;

  const _SuccessStep({
    super.key,
    required this.entry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isClockedIn = entry.isOpen;
    final accent = isClockedIn ? AppColors.deepGreen : AppColors.amber;
    final timeFmt = DateFormat('h:mm a');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isClockedIn
                  ? Icons.login_rounded
                  : Icons.logout_rounded,
              color: accent,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            isClockedIn ? 'Clocked In!' : 'Clocked Out!',
            style: AppTextStyles.h1(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            entry.employeeName,
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Info cards
          if (isClockedIn)
            _InfoRow(
              label: 'Arrivé à',
              value: timeFmt.format(entry.clockIn),
              icon: Icons.login_rounded,
              color: accent,
              isDark: isDark,
            )
          else ...[
            _InfoRow(
              label: 'Arrivé à',
              value: timeFmt.format(entry.clockIn),
              icon: Icons.login_rounded,
              color: AppColors.primaryBlue,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Parti à',
              value: timeFmt.format(entry.clockOut!),
              icon: Icons.logout_rounded,
              color: accent,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Heures totales',
              value: entry.durationLabel,
              icon: Icons.timer_outlined,
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              isDark: isDark,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Fermeture automatique…',
            style:
                AppTextStyles.caption(color: isDark ? AppColors.coolGray : AppColors.darkGray),
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final TimeclockEntry entry;
  final bool isDark;
  final Stream<int> ticker;

  const _StatusCard({
    required this.entry,
    required this.isDark,
    required this.ticker,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');

    return StreamBuilder<int>(
      stream: ticker,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            border:
                Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Actuellement en service',
                      style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniInfo(
                    label: 'Depuis',
                    value: timeFmt.format(entry.clockIn),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 16),
                  _MiniInfo(
                    label: 'Durée',
                    value: entry.durationLabel,
                    isDark: isDark,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _MiniInfo(
      {required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        Text(value,
            style: AppTextStyles.price(
                color:
                    isDark ? AppColors.warmWhite : AppColors.nearBlack)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTextStyles.caption(
                    color:
                        isDark ? AppColors.coolGray : AppColors.darkGray)),
          ),
          Text(
            value,
            style: AppTextStyles.price(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final StaffRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
      ),
      child: Text(
        staffRoleDisplayLabel(role),
        style: AppTextStyles.caption(
            color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
      ),
    );
  }
}

// ─── Modal compact PIN dots ───────────────────────────────────────────────────

class _ModalPinDots extends StatelessWidget {
  final String digits;
  final int pinLen;
  final bool isDark;

  const _ModalPinDots(
      {required this.digits, required this.pinLen, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final filled = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final empty = isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pinLen, (i) {
        final f = i < digits.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: f ? 18 : 16,
          height: f ? 18 : 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: f ? filled : Colors.transparent,
            border: Border.all(color: f ? filled : empty, width: 2),
          ),
        );
      }),
    );
  }
}

// ─── Modal compact keypad ─────────────────────────────────────────────────────

class _ModalKeypad extends StatelessWidget {
  final bool isDark;
  final bool busy;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const _ModalKeypad({
    required this.isDark,
    required this.busy,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final keyBg = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);
    const keyH = 52.0;
    const gap = 8.0;

    Widget key({required Widget child, required VoidCallback? onTap}) {
      return Expanded(
        child: SizedBox(
          height: keyH,
          child: Material(
            color: keyBg,
            borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : onTap,
              splashColor: AppColors.primaryBlue.withValues(alpha: 0.1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusButton),
                  border: Border.all(color: border),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    final labelStyle = GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
    );

    Widget row3(List<String> ds) => Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                key(
                  onTap: () => onDigit(ds[i]),
                  child: Text(ds[i], style: labelStyle),
                ),
              ],
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row3(['1', '2', '3']),
        row3(['4', '5', '6']),
        row3(['7', '8', '9']),
        Row(
          children: [
            key(
              onTap: onClear,
              child: Icon(Icons.close_rounded,
                  size: 20,
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
            const SizedBox(width: gap),
            key(
              onTap: () => onDigit('0'),
              child: Text('0', style: labelStyle),
            ),
            const SizedBox(width: gap),
            key(
              onTap: onBackspace,
              child: Icon(Icons.backspace_outlined,
                  size: 18,
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
          ],
        ),
      ],
    );
  }
}

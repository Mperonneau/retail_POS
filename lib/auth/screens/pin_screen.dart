import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/permissions/first_allowed_home_route.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/device_session_provider.dart';
import '../../core/providers/permission_settings_provider.dart';
import '../../core/providers/staff_session_provider.dart';
import '../../core/widgets/timeclock_modal.dart';

// ─── Design tokens — PIN screen only ────────────────────────────────────────
const Color _kBg     = Color(0xFF180F2E);
const Color _kDiv    = Color(0xFF2A1E50);
const Color _kKeyBg  = Color(0xFF2E2060);
const Color _kLabel  = Color(0xB3FFFFFF);
const Color _kError  = Color(0xFFFFAB91);
const Color _kGlow   = Color(0xFF7C3AED);

// Fixed spacing constants used to align action buttons with the keypad top
const double _kDotsH       = 22.0;
const double _kDotsGapB    = 10.0;
const double _kErrorH      = 22.0;
const double _kErrorGapB   = 24.0;
const double _kActionOffset = _kDotsH + _kDotsGapB + _kErrorH + _kErrorGapB;

// ─────────────────────────────────────────────────────────────────────────────

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  String _digits = '';
  String? _error;
  bool _busy = false;
  static const int _pinLength = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authProvider);
      final session = ref.read(deviceSessionProvider);
      if (auth.status != AuthStatus.authenticated && session.profile != null) {
        ref.read(deviceSessionProvider.notifier).applyStoredAuth(ref);
      }
    });
  }

  void _append(String d) {
    if (_busy || _digits.length >= _pinLength) return;
    setState(() {
      _digits += d;
      _error = null;
    });
    HapticFeedback.lightImpact();
    if (_digits.length == _pinLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  void _backspace() {
    if (_busy || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  void _clearAll() {
    if (_busy) return;
    setState(() {
      _digits = '';
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  void _onTimeclock() {
    HapticFeedback.lightImpact();
    showTimeclockModal(context);
  }

  Future<void> _submit() async {
    if (_busy || _digits.length != _pinLength) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final err = ref.read(staffSessionProvider.notifier).signInWithPin(_digits);
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
        _digits = '';
      });
      return;
    }

    final module = ref.read(authProvider).module;
    final staff  = ref.read(staffSessionProvider)!;
    final perms  = ref.read(effectivePermissionsProvider);
    setState(() => _busy = false);
    context.go(firstAllowedHomeRoute(module: module, role: staff.role, perms: perms));
  }

  void _signOut() {
    if (_busy) return;
    ref.read(staffSessionProvider.notifier).clear();
    ref.read(authProvider.notifier).logout();
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(authProvider).businessName ?? 'Business';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth >= 700;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 37,
                      child: _BrandingPanel(businessName: business),
                    ),
                    Container(width: 1, color: _kDiv),
                    Expanded(
                      flex: 63,
                      child: _EntryPanel(
                        digits: _digits,
                        pinLength: _pinLength,
                        error: _error,
                        busy: _busy,
                        onAppend: _append,
                        onBackspace: _backspace,
                        onClear: _clearAll,
                        onTimeclock: _onTimeclock,
                        onSignOut: _signOut,
                      ),
                    ),
                  ],
                );
              }

              return _EntryPanel(
                businessName: business,
                showBranding: true,
                digits: _digits,
                pinLength: _pinLength,
                error: _error,
                busy: _busy,
                onAppend: _append,
                onBackspace: _backspace,
                onClear: _clearAll,
                onTimeclock: _onTimeclock,
                onSignOut: _signOut,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Branding panel ──────────────────────────────────────────────────────────

class _BrandingPanel extends StatelessWidget {
  final String businessName;
  const _BrandingPanel({required this.businessName});

  @override
  Widget build(BuildContext context) {
    final initial = businessName.trim().isNotEmpty
        ? businessName.trim()[0].toUpperCase()
        : 'B';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E1238), Color(0xFF140B26)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          // Glow + logo tile
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kGlow.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: _kGlow.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: GoogleFonts.poppins(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: _kBg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            businessName,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              'BizManager Haiti',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _kLabel,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          // Demo PINs — here in the branding panel, out of the way
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo PINs',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.45),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                _demoPin('1234', 'Cashier'),
                _demoPin('1111', 'Waiter'),
                _demoPin('2222', 'Manager'),
                _demoPin('3333', 'Admin'),
                _demoPin('4444', 'Kitchen'),
                _demoPin('8888', 'Reception'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _demoPin(String pin, String role) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Text(
            pin,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.55),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            role,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entry panel ─────────────────────────────────────────────────────────────

class _EntryPanel extends StatelessWidget {
  final String? businessName;
  final bool showBranding;
  final String digits;
  final int pinLength;
  final String? error;
  final bool busy;
  final void Function(String) onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onTimeclock;
  final VoidCallback onSignOut;

  const _EntryPanel({
    this.businessName,
    this.showBranding = false,
    required this.digits,
    required this.pinLength,
    required this.error,
    required this.busy,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onTimeclock,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, outer) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: outer.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 36,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showBranding && businessName != null) ...[
                        _CompactBranding(businessName: businessName!),
                        const SizedBox(height: 28),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          thickness: 1,
                        ),
                        const SizedBox(height: 28),
                      ],
                      _PinContent(
                        digits: digits,
                        pinLength: pinLength,
                        error: error,
                        busy: busy,
                        onAppend: onAppend,
                        onBackspace: onBackspace,
                        onClear: onClear,
                        onTimeclock: onTimeclock,
                        onSignOut: onSignOut,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── PIN content (title + keypad row + action buttons) ───────────────────────
// Uses its own LayoutBuilder so key sizing adapts to available width.

class _PinContent extends StatelessWidget {
  final String digits;
  final int pinLength;
  final String? error;
  final bool busy;
  final void Function(String) onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onTimeclock;
  final VoidCallback onSignOut;

  const _PinContent({
    required this.digits,
    required this.pinLength,
    required this.error,
    required this.busy,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onTimeclock,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        const actionW  = 100.0;
        const colGap   = 20.0;
        const keyGap   = 10.0;

        final keypadAvail = box.maxWidth - actionW - colGap;
        final keySize     = ((keypadAvail - 2 * keyGap) / 3).clamp(52.0, 114.0);
        final keypadW     = 3 * keySize + 2 * keyGap;
        final keypadH     = 4 * keySize + 3 * keyGap;
        final btnH        = (keypadH - keyGap) / 2;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title — centered across the full row (keypad + buttons)
            Text(
              'Enter your passcode',
              style: GoogleFonts.poppins(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Keypad column + action buttons side by side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Keypad column ───────────────────────────────────────
                SizedBox(
                  width: keypadW,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dots centered to keypad width
                      _PinDots(digits: digits, pinLength: pinLength),
                      const SizedBox(height: _kDotsGapB),
                      // Error (reserved space — no layout jump)
                      SizedBox(
                        height: _kErrorH,
                        child: error != null
                            ? Text(
                                error!,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _kError,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                      ),
                      const SizedBox(height: _kErrorGapB),
                      // Pure 3×4 keypad grid
                      _PinKeypadGrid(
                        keySize: keySize,
                        busy: busy,
                        onDigit: onAppend,
                        onBackspace: onBackspace,
                        onClear: onClear,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: colGap),

                // ── Action buttons ──────────────────────────────────────
                // Top offset aligns these with the keypad grid (skips the
                // dots + error section above the grid).
                Padding(
                  padding: const EdgeInsets.only(top: _kActionOffset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionBtn(
                        width: actionW,
                        height: btnH,
                        icon: Icons.access_time_rounded,
                        label: 'Timeclock',
                        onTap: onTimeclock,
                      ),
                      const SizedBox(height: keyGap),
                      _ActionBtn(
                        width: actionW,
                        height: btnH,
                        icon: Icons.logout_rounded,
                        label: 'Exit',
                        onTap: onSignOut,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Compact branding (narrow screens) ───────────────────────────────────────

class _CompactBranding extends StatelessWidget {
  final String businessName;
  const _CompactBranding({required this.businessName});

  @override
  Widget build(BuildContext context) {
    final initial = businessName.trim().isNotEmpty
        ? businessName.trim()[0].toUpperCase()
        : 'B';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _kGlow.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: _kBg,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          businessName,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
        const SizedBox(height: 4),
        Text(
          'BizManager Haiti',
          style: GoogleFonts.inter(fontSize: 12, color: _kLabel),
        ),
      ],
    );
  }
}

// ─── PIN dots ─────────────────────────────────────────────────────────────────

class _PinDots extends StatelessWidget {
  final String digits;
  final int pinLength;
  const _PinDots({required this.digits, required this.pinLength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(pinLength, (i) {
        final filled = i < digits.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: filled ? _kDotsH : _kDotsH - 2,
          height: filled ? _kDotsH : _kDotsH - 2,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Colors.white : Colors.transparent,
            border: Border.all(
              color: filled ? Colors.white : Colors.white.withValues(alpha: 0.5),
              width: filled ? 2.5 : 2,
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

// ─── Pure 3×4 keypad grid ────────────────────────────────────────────────────

class _PinKeypadGrid extends StatelessWidget {
  final double keySize;
  final bool busy;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const _PinKeypadGrid({
    required this.keySize,
    required this.busy,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const keyGap = 10.0;

    final digitStyle = GoogleFonts.poppins(
      fontSize: (keySize * 0.36).clamp(20.0, 32.0),
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final iconSz = (keySize * 0.38).clamp(20.0, 30.0);

    Widget buildKey({
      required Widget child,
      required VoidCallback? onTap,
    }) {
      return Container(
        width: keySize,
        height: keySize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: _kKeyBg,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : onTap,
            splashColor: Colors.white.withValues(alpha: 0.1),
            highlightColor: Colors.white.withValues(alpha: 0.07),
            child: SizedBox(
              width: keySize,
              height: keySize,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    Widget digitKey(String d) => buildKey(
      onTap: () => onDigit(d),
      child: Text(d, style: digitStyle),
    );

    Widget keyRow(List<String> labels, {bool addBottomGap = true}) {
      return Padding(
        padding: EdgeInsets.only(bottom: addBottomGap ? keyGap : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: keyGap),
              digitKey(labels[i]),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        keyRow(['1', '2', '3']),
        keyRow(['4', '5', '6']),
        keyRow(['7', '8', '9']),
        // Bottom row: clear · 0 · backspace
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildKey(
              onTap: onClear,
              child: Icon(Icons.close_rounded, color: Colors.white, size: iconSz),
            ),
            const SizedBox(width: keyGap),
            digitKey('0'),
            const SizedBox(width: keyGap),
            buildKey(
              onTap: onBackspace,
              child: Icon(Icons.backspace_outlined, color: Colors.white, size: iconSz * 0.9),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Action button (Timeclock / Exit) ────────────────────────────────────────
// Intentionally styled differently from the keypad keys:
// — Outlined / glass look (not solid purple)
// — More rounded (14px vs 12px)
// — No drop shadow
// — Softer icon + label layout

class _ActionBtn extends StatelessWidget {
  final double width;
  final double height;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _ActionBtn({
    required this.width,
    required this.height,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDestructive
        ? Colors.redAccent.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.18);
    final bgColor = isDestructive
        ? Colors.redAccent.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.06);
    final contentColor = isDestructive
        ? Colors.redAccent.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.75);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: contentColor, size: 24),
              const SizedBox(height: 7),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: contentColor,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

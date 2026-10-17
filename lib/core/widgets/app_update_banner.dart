import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/app_update.dart';
import '../services/page_reload.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_button.dart';

/// Shows a reload banner when the server has a newer web build.
class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost({
    super.key,
    required this.child,
    this.checker,
    this.interval = const Duration(minutes: 10),
  });

  final Widget child;
  final AppUpdateChecker? checker;
  final Duration interval;

  @override
  State<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  late final AppUpdateChecker _checker = widget.checker ?? AppUpdateChecker();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checker.addListener(_changed);
    if (_checker.enabled) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_checker.check());
      _timer = Timer.periodic(widget.interval, (_) => _checker.check());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _checker.removeListener(_changed);
    if (widget.checker == null) _checker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checker.check());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _holdForCheckout(BuildContext context) {
    try {
      final path = GoRouterState.of(context).uri.path;
      return path.contains('cash') ||
          path.contains('payment') ||
          path.contains('checkout') ||
          path.contains('/pos');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _checker.visible;
    final show = status.mode != AppUpdateMode.none && !_holdForCheckout(context);
    return Stack(
      children: [
        widget.child,
        if (show && status.mode == AppUpdateMode.soft)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _SoftBanner(
                  onReload: () => _checker.apply(),
                  onDismiss: _checker.dismiss,
                ),
              ),
            ),
          ),
        if (show && status.mode == AppUpdateMode.forced)
          const Positioned.fill(child: _ForcedUpdate()),
      ],
    );
  }
}

class _SoftBanner extends StatelessWidget {
  const _SoftBanner({required this.onReload, required this.onDismiss});

  final VoidCallback onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: const ValueKey('app-update-banner'),
      color: isDark ? AppColors.darkSurface : AppColors.white,
      elevation: 6,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE6E6E6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt, color: AppColors.primaryBlue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Une nouvelle version est disponible.',
                style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Recharger',
              compact: true,
              fullWidth: false,
              onPressed: onReload,
            ),
            IconButton(
              key: const ValueKey('app-update-dismiss'),
              icon: Icon(
                Icons.close,
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
                size: 20,
              ),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForcedUpdate extends StatelessWidget {
  const _ForcedUpdate();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: const ValueKey('app-update-forced'),
      color: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update_alt, color: AppColors.primaryBlue, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Mise à jour requise',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h1(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cette version n\'est plus prise en charge. Rechargez pour continuer.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Recharger',
                    onPressed: reloadApp,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

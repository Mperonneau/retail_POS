import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/providers/device_session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait([
      ref.read(deviceSessionProvider.notifier).restore(),
      Future.delayed(AppConstants.splashDuration),
    ]);
    if (!mounted) return;
    final session = ref.read(deviceSessionProvider);
    if (session.isPaired) {
      ref.read(deviceSessionProvider.notifier).applyStoredAuth(ref);
      context.go(AppRoutes.pin);
    } else {
      context.go(AppRoutes.pairDevice);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo mark
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.amber.withValues(alpha: 0.4),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.business_center_rounded,
                    color: AppColors.nearBlack,
                    size: 48,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing24),
                Text(
                  'BizManager',
                  style: AppTextStyles.appName(color: AppColors.white),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  'Haiti',
                  style: AppTextStyles.appName(color: AppColors.amber).copyWith(fontSize: 28),
                ),
                const SizedBox(height: AppConstants.spacing12),
                Text(
                  'Simplifying Business, One Transaction at a Time',
                  style: AppTextStyles.caption(color: AppColors.sidebarIcon),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacing48),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.amber.withValues(alpha: 0.6),
                    ),
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

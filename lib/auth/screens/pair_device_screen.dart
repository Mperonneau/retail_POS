import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/providers/device_session_provider.dart';
import '../../core/services/device_pairing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_input.dart';

/// One-time connection for a new register. After this, staff use a PIN.
class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(deviceSessionProvider.notifier).pairWithCode(_code.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    ref.read(deviceSessionProvider.notifier).applyStoredAuth(ref);
    context.go(AppRoutes.pin);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = ref.watch(deviceSessionProvider);
    final offline = session.ready && !session.online;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(AppConstants.spacing32),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                  boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect this device',
                      style: AppTextStyles.h1(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the code from Connected devices. After this, the register opens with a PIN.',
                      style: AppTextStyles.body(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                    if (offline) ...[
                      const SizedBox(height: 16),
                      Text(
                        'No internet. A device code needs a connection.',
                        style: AppTextStyles.body(color: AppColors.boldRed),
                      ),
                    ],
                    const SizedBox(height: 24),
                    AppInput(
                      label: 'Device code',
                      hint: '7KQ2-M9XD',
                      controller: _code,
                      errorText: _error,
                      prefixIcon: Icons.devices_other_outlined,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        final formatted = normalizeDeviceCode(value);
                        if (formatted != value) {
                          _code.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(offset: formatted.length),
                          );
                        }
                        if (_error != null) setState(() => _error = null);
                      },
                      onEditingComplete: _busy || offline ? null : _submit,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: _busy ? 'Connecting…' : 'Connect',
                      isLoading: _busy,
                      onPressed: _busy || offline ? null : _submit,
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'Sign in with email',
                      variant: AppButtonVariant.ghost,
                      onPressed: _busy ? null : () => context.go(AppRoutes.login),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/device_session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_input.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;
  String _selectedLang = 'EN';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    setState(() {
      _emailError = _emailCtrl.text.isEmpty ? 'Email or phone is required' : null;
      _passwordError = _passwordCtrl.text.isEmpty ? 'Password is required' : null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    const userName = 'Jean-Marc Dupont';
    const businessName = 'Boutique Soleil';
    await ref.read(deviceSessionProvider.notifier).authorizeThisRegister(
          userName: userName,
          businessName: businessName,
          module: ActiveModule.retail,
        );
    ref.read(authProvider.notifier).login(
      userName: userName,
      businessName: businessName,
      module: ActiveModule.retail,
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    context.go(AppRoutes.pin);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      body: SafeArea(
        child: Stack(
          children: [
            // Background decoration
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.skyBlue.withValues(alpha: 0.06) : AppColors.primaryBlue.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.amber.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Language selector
            Positioned(
              top: 16,
              right: 16,
              child: _LanguageSelector(
                selected: _selectedLang,
                onChanged: (v) => setState(() => _selectedLang = v),
              ),
            ),
            // Center card
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppConstants.spacing24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 420 : double.infinity),
                  child: Container(
                    padding: const EdgeInsets.all(AppConstants.spacing32),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.white,
                      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                      boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.business_center_rounded,
                                  color: AppColors.amber, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Text('BizManager Haiti',
                                style: AppTextStyles.h3(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spacing24),
                        Text('Welcome back',
                            style: AppTextStyles.h1(
                              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                            )),
                        const SizedBox(height: AppConstants.spacing4),
                        Text('Sign in to continue',
                            style: AppTextStyles.body(
                              color: isDark ? AppColors.coolGray : AppColors.darkGray,
                            )),
                        const SizedBox(height: AppConstants.spacing32),
                        AppInput(
                          label: 'Email or Phone Number',
                          hint: 'e.g. manager@hotel.ht',
                          controller: _emailCtrl,
                          errorText: _emailError,
                          prefixIcon: Icons.person_outline,
                          keyboardType: TextInputType.emailAddress,
                          inputFormatters: InputFormatters.loginIdentifier,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppConstants.spacing16),
                        AppInput(
                          label: 'Password',
                          hint: 'Enter your password',
                          controller: _passwordCtrl,
                          errorText: _passwordError,
                          obscureText: true,
                          showToggleObscure: true,
                          prefixIcon: Icons.lock_outline,
                          textInputAction: TextInputAction.done,
                          onEditingComplete: _onLogin,
                        ),
                        const SizedBox(height: AppConstants.spacing12),
                        Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                activeColor: AppColors.primaryBlue,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text('Remember me',
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                                  )),
                            ),
                            TextButton(
                              onPressed: () => context.go(AppRoutes.forgotPassword),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('Forgot Password?',
                                  style: AppTextStyles.body(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spacing24),
                        AppButton(
                          label: 'Sign In',
                          onPressed: _onLogin,
                          isLoading: _isLoading,
                        ),
                        const SizedBox(height: AppConstants.spacing16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text("Don't have an account? ",
                                style: AppTextStyles.body(
                                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                                )),
                            TextButton(
                              onPressed: () => context.go(AppRoutes.register),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('Register',
                                  style: AppTextStyles.body(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                                      .copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _LanguageSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<String>(
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 16, color: isDark ? AppColors.coolGray : AppColors.darkGray),
            const SizedBox(width: 4),
            Text(selected, style: AppTextStyles.caption()),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: isDark ? AppColors.coolGray : AppColors.darkGray),
          ],
        ),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'KR', child: Text('Kreyòl')),
        const PopupMenuItem(value: 'FR', child: Text('Français')),
        const PopupMenuItem(value: 'EN', child: Text('English')),
      ],
    );
  }
}

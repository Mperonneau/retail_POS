import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_input.dart';

enum _ForgotStep { email, otp, newPassword }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _ForgotStep _step = _ForgotStep.email;
  final _emailCtrl = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _isLoading = false;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  void _startResendTimer() {
    _resendCountdown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _onContinue() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (_step == _ForgotStep.email) {
        _step = _ForgotStep.otp;
        _startResendTimer();
      } else if (_step == _ForgotStep.otp)
        _step = _ForgotStep.newPassword;
      else
        context.go(AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
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
                  boxShadow:
                      isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () {
                        if (_step == _ForgotStep.email) {
                          context.go(AppRoutes.login);
                        } else {
                          setState(() =>
                              _step = _ForgotStep.values[_step.index - 1]);
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_rounded,
                              size: 16,
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue),
                          const SizedBox(width: 4),
                          Text('Back',
                              style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.skyBlue
                                      : AppColors.primaryBlue)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    _buildStepIndicator(),
                    const SizedBox(height: AppConstants.spacing24),
                    AnimatedSwitcher(
                      duration: AppConstants.animNormal,
                      child: _buildStepContent(),
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    AppButton(
                      label: _step == _ForgotStep.newPassword
                          ? 'Reset Password'
                          : 'Continue',
                      onPressed: _onContinue,
                      isLoading: _isLoading,
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

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (i) {
        final isActive = i == _step.index;
        final isDone = i < _step.index;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
            child: AnimatedContainer(
              duration: AppConstants.animNormal,
              height: 4,
              decoration: BoxDecoration(
                color: isDone || isActive
                    ? AppColors.amber
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (_step) {
      case _ForgotStep.email:
        return Column(
          key: const ValueKey('email'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forgot Password?', style: AppTextStyles.h1()),
            const SizedBox(height: AppConstants.spacing8),
            Text("Enter your email or phone and we'll send you a reset code.",
                style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: AppConstants.spacing24),
            AppInput(
              label: 'Email or Phone Number',
              hint: 'e.g. manager@hotel.ht',
              controller: _emailCtrl,
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: InputFormatters.loginIdentifier,
            ),
          ],
        );
      case _ForgotStep.otp:
        return Column(
          key: const ValueKey('otp'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter OTP Code', style: AppTextStyles.h1()),
            const SizedBox(height: AppConstants.spacing8),
            Text('We sent a 6-digit code to ${_emailCtrl.text}',
                style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: AppConstants.spacing24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                  6,
                  (i) => _OtpBox(
                      controller: _otpControllers[i],
                      index: i,
                      controllers: _otpControllers)),
            ),
            const SizedBox(height: AppConstants.spacing16),
            Center(
              child: _resendCountdown > 0
                  ? Text(
                      "Resend code in ${_resendCountdown}s",
                      style: AppTextStyles.caption(
                          color: isDark ? AppColors.coolGray : AppColors.darkGray),
                    )
                  : TextButton(
                      onPressed: () {
                        _startResendTimer();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('OTP code resent!')),
                        );
                      },
                      child: Text("Didn't receive code? Resend",
                          style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue)),
                    ),
            ),
          ],
        );
      case _ForgotStep.newPassword:
        return Column(
          key: const ValueKey('newPass'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Password', style: AppTextStyles.h1()),
            const SizedBox(height: AppConstants.spacing8),
            Text('Choose a strong password for your account.',
                style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: AppConstants.spacing24),
            AppInput(
              label: 'New Password',
              hint: 'At least 8 characters',
              controller: _newPassCtrl,
              obscureText: true,
              showToggleObscure: true,
              prefixIcon: Icons.lock_outline,
            ),
            const SizedBox(height: AppConstants.spacing16),
            AppInput(
              label: 'Confirm Password',
              hint: 'Repeat your password',
              controller: _confirmPassCtrl,
              obscureText: true,
              showToggleObscure: true,
              prefixIcon: Icons.lock_outline,
            ),
          ],
        );
    }
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final int index;
  final List<TextEditingController> controllers;

  const _OtpBox({
    required this.controller,
    required this.index,
    required this.controllers,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 44,
      height: 52,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: InputFormatters.digitsOnly,
        style: AppTextStyles.price(
            color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            borderSide: BorderSide(
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                width: 2),
          ),
        ),
        onChanged: (v) {
          if (v.isNotEmpty && index < 5) {
            FocusScope.of(context).nextFocus();
          }
        },
      ),
    );
  }
}

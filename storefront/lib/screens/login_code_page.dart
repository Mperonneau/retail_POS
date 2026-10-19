import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';

import '../api.dart';
import '../countries.dart';
import '../session.dart';

/// Placeholder code step. Any code continues until Firebase sends a real one.
class LoginCodePage extends StatefulWidget {
  const LoginCodePage({super.key});

  @override
  State<LoginCodePage> createState() => _LoginCodePageState();
}

class _LoginCodePageState extends State<LoginCodePage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onChanged);
    if (loginDraft.national.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
    }
  }

  @override
  void dispose() {
    _code.removeListener(_onChanged);
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_code.text.length == 6 && !_busy) _submit();
  }

  Future<void> _submit() async {
    if (_busy || _code.text.length != 6) return;
    _busy = true;
    setState(() => _error = null);
    try {
      final result = await Session.instance.verifyCode(
        phoneNumber: loginDraft.national,
        countryCode: loginDraft.iso,
        code: _code.text,
      );
      if (!mounted) return;
      if (result.registered) {
        loginDraft.clear();
        context.go('/');
        return;
      }
      loginDraft.signupToken = result.signupToken;
      context.go('/login/profil');
    } on ApiException catch (error) {
      _code.clear();
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = _code.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Text('Code', style: AppTextStyles.h1(color: AppColors.nearBlack)),
        const SizedBox(height: 8),
        Text(
          'Entrez un code pour ${loginDraft.displayPhone}.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  for (var index = 0; index < 6; index++)
                    Expanded(
                      child: Container(
                        height: 56,
                        margin: EdgeInsets.only(left: index == 0 ? 0 : 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: digits.length == index
                                ? AppColors.primaryBlue
                                : const Color(0xFFD5D1C8),
                            width: digits.length == index ? 1.6 : 1,
                          ),
                        ),
                        child: Text(
                          index < digits.length ? digits[index] : '',
                          style: AppTextStyles.h2(color: AppColors.nearBlack),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 56,
                child: TextField(
                  controller: _code,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  showCursor: false,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.errorText()),
        ],
        const SizedBox(height: 20),
        AppButton(
          label: 'Continuer',
          isLoading: _busy,
          onPressed: _busy || digits.length != 6 ? null : _submit,
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'Changer de numéro',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => context.go('/login'),
        ),
      ],
    );
  }
}

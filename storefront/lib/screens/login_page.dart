import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';

import '../api.dart';
import '../countries.dart';
import '../session.dart';

/// Phone number only. The country flag and calling code sit on the same row.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone.text = loginDraft.national.isEmpty
        ? ''
        : formatPhone(loginDraft.country, loginDraft.national);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parts = splitPhone(_phone.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.requestCode(
        phoneNumber: parts.national,
        countryCode: parts.country.iso,
      );
      if (!mounted) return;
      loginDraft
        ..iso = parts.country.iso
        ..national = parts.national
        ..signupToken = '';
      context.go('/login/code');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Text('Connexion', style: AppTextStyles.h1(color: AppColors.nearBlack)),
        const SizedBox(height: 8),
        Text(
          'Entrez votre numéro de téléphone. Vous indiquerez ensuite un code pour continuer.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const SizedBox(height: 20),
        PhoneField(
          controller: _phone,
          label: 'Téléphone',
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onEditingComplete: () {
            if (!_busy) _submit();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.errorText()),
        ],
        const SizedBox(height: 20),
        AppButton(label: 'Continuer', isLoading: _busy, onPressed: _busy ? null : _submit),
        const SizedBox(height: 8),
        AppButton(
          label: 'Continuer en invité',
          variant: AppButtonVariant.ghost,
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }
}

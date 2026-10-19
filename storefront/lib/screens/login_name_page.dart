import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_input.dart';

import '../api.dart';
import '../countries.dart';
import '../session.dart';

/// New numbers land here after the code. The country is already chosen.
class LoginNamePage extends StatefulWidget {
  const LoginNamePage({super.key});

  @override
  State<LoginNamePage> createState() => _LoginNamePageState();
}

class _LoginNamePageState extends State<LoginNamePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (loginDraft.signupToken.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.register(
        signupToken: loginDraft.signupToken,
        displayName: _name.text.trim(),
        email: _email.text.trim(),
      );
      if (!mounted) return;
      loginDraft.clear();
      context.go('/');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = countryName(loginDraft.iso);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Text('Votre compte', style: AppTextStyles.h1(color: AppColors.nearBlack)),
        const SizedBox(height: 8),
        Text(
          country.isEmpty
              ? 'Indiquez votre nom complet pour terminer. L\'e-mail est facultatif.'
              : 'Indiquez votre nom complet pour terminer. Votre pays, $country, est enregistré avec le numéro. L\'e-mail est facultatif.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const SizedBox(height: 20),
        AppInput(
          label: 'Nom complet',
          controller: _name,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        AppInput(
          label: 'E-mail (facultatif)',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onEditingComplete: _busy ? null : _submit,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.errorText()),
        ],
        const SizedBox(height: 20),
        AppButton(label: 'Continuer', isLoading: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}

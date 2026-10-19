import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_input.dart';

import '../api.dart';
import '../session.dart';

/// Phone and a personal code. No SMS is sent: the code is chosen by the customer.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.login(
        displayName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        pin: _pin.text.trim(),
      );
      if (!mounted) return;
      context.go('/profile');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
          'Entrez votre numéro et un code personnel de 4 à 6 chiffres. '
          'La première fois, le compte est créé. Ensuite, le même code vous reconnecte. '
          'Vous pouvez aussi commander sans compte.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const SizedBox(height: 20),
        AppInput(label: 'Nom', controller: _name, textInputAction: TextInputAction.next),
        const SizedBox(height: 12),
        AppInput(
          label: 'Téléphone',
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        AppInput(
          label: 'Code personnel',
          controller: _pin,
          obscureText: true,
          showToggleObscure: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
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

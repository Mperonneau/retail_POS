import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late DialCountry _country;

  @override
  void initState() {
    super.initState();
    _country = loginDraft.country;
    _phone.text = loginDraft.national;
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await showCountryPicker(context, selected: _country.iso);
    if (picked != null && mounted) setState(() => _country = picked);
  }

  Future<void> _submit() async {
    final national = _phone.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.requestCode(phoneNumber: national, countryCode: _country.iso);
      if (!mounted) return;
      loginDraft
        ..iso = _country.iso
        ..national = national
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
          'Entrez votre numéro de téléphone. Un code vous sera envoyé pour vous connecter.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const SizedBox(height: 20),
        Text('Téléphone', style: AppTextStyles.inputLabel(color: AppColors.darkGray)),
        const SizedBox(height: 4),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          enabled: !_busy,
          onSubmitted: (_) => _busy ? null : _submit(),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
            LengthLimitingTextInputFormatter(18),
          ],
          style: AppTextStyles.body(color: AppColors.nearBlack),
          decoration: InputDecoration(
            hintText: 'Numéro',
            prefixIcon: InkWell(
              onTap: _busy ? null : _pickCountry,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_country.flag, style: flagStyle),
                    const SizedBox(width: 6),
                    Text(
                      '+${_country.dial}',
                      style: AppTextStyles.body(color: AppColors.nearBlack),
                    ),
                    Icon(Icons.expand_more, size: 18, color: AppColors.darkGray),
                  ],
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 48),
          ),
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

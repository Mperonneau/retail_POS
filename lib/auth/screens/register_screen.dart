import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/models/currency_settings.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_input.dart';

// Haiti departments (official administrative regions)
const _haitiDepartments = [
  'Artibonite',
  'Centre',
  "Grand'Anse",
  'Nippes',
  'Nord',
  'Nord-Est',
  'Nord-Ouest',
  'Ouest',
  'Sud',
  'Sud-Est',
];

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 0 — Email verification
  final _emailCtrl = TextEditingController();
  int _emailSubStep = 0; // 0 = email entry, 1 = code entry
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  String _codeError = '';
  String _emailError = '';

  // Step 1 — Contact info
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _nameError = '';

  // Step 2 — Business details
  final _bizNameCtrl = TextEditingController();
  String _bizNameError = '';

  // Step 3 — Business address (country locked to Haiti)
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String? _selectedDepartment;
  final _zipCtrl = TextEditingController();
  String _addressError = '';
  String _cityError = '';
  String _departmentError = '';

  // Step 4 — Module
  ActiveModule? _selectedModule;
  String _moduleError = '';

  // Step 5 — Currency (country auto-filled from address, locked)
  String _currency = 'both';
  final _rateCtrl = TextEditingController(text: '135');

  // Step 6 — Language
  String _language = 'fr';

  // Step 7 — Password + T&C
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _termsAccepted = false;
  String _passwordError = '';
  String _confirmError = '';
  String _termsError = '';

  static const _totalSteps = 8;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bizNameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _zipCtrl.dispose();
    _rateCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_emailSubStep == 0) {
          final email = _emailCtrl.text.trim();
          if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
            setState(() => _emailError = 'Veuillez saisir une adresse e-mail valide.');
            return false;
          }
          setState(() => _emailError = '');
          return true;
        } else {
          if (_codeCtrl.text.trim() != '123456') {
            setState(() => _codeError = 'Code incorrect. Veuillez réessayer.');
            return false;
          }
          setState(() => _codeError = '');
          return true;
        }
      case 1:
        if (_nameCtrl.text.trim().isEmpty) {
          setState(() => _nameError = 'Veuillez saisir votre nom complet.');
          return false;
        }
        setState(() => _nameError = '');
        return true;
      case 2:
        if (_bizNameCtrl.text.trim().isEmpty) {
          setState(() => _bizNameError = 'Veuillez saisir le nom de votre commerce.');
          return false;
        }
        setState(() => _bizNameError = '');
        return true;
      case 3:
        bool ok = true;
        if (_addressCtrl.text.trim().isEmpty) {
          setState(() => _addressError = 'L\'adresse est obligatoire.');
          ok = false;
        } else {
          setState(() => _addressError = '');
        }
        if (_cityCtrl.text.trim().isEmpty) {
          setState(() => _cityError = 'La ville est obligatoire.');
          ok = false;
        } else {
          setState(() => _cityError = '');
        }
        if (_selectedDepartment == null) {
          setState(() => _departmentError = 'Veuillez choisir un département.');
          ok = false;
        } else {
          setState(() => _departmentError = '');
        }
        return ok;
      case 4:
        if (_selectedModule == null) {
          setState(() => _moduleError = 'Veuillez choisir un module.');
          return false;
        }
        setState(() => _moduleError = '');
        return true;
      case 7:
        bool ok = true;
        if (_passwordCtrl.text.length < 8) {
          setState(() => _passwordError = 'Le mot de passe doit contenir au moins 8 caractères.');
          ok = false;
        } else {
          setState(() => _passwordError = '');
        }
        if (_passwordCtrl.text != _confirmCtrl.text) {
          setState(() => _confirmError = 'Les mots de passe ne correspondent pas.');
          ok = false;
        } else if (_passwordCtrl.text.isNotEmpty) {
          setState(() => _confirmError = '');
        }
        if (!_termsAccepted) {
          setState(() => _termsError = 'Vous devez accepter les conditions générales pour continuer.');
          ok = false;
        } else {
          setState(() => _termsError = '');
        }
        return ok;
      default:
        return true;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  Future<void> _onNext() async {
    if (_currentStep == 0) {
      if (_emailSubStep == 0) {
        if (!_validateCurrentStep()) return;
        setState(() => _isLoading = true);
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _emailSubStep = 1;
          _codeSent = true;
        });
        _snack('Code envoyé à ${_emailCtrl.text.trim()}. (Démo : 123456)');
        return;
      } else {
        if (!_validateCurrentStep()) return;
        setState(() => _currentStep = 1);
        return;
      }
    }

    if (!_validateCurrentStep()) return;

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      await _createAccount();
    }
  }

  Future<void> _createAccount() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    const countryCode = 'HT';
    final mode = switch (_currency) {
      'htg' => BusinessCurrencyMode.localOnly,
      'usd' => BusinessCurrencyMode.usdOnly,
      _ => BusinessCurrencyMode.both,
    };
    ref.read(currencySettingsProvider.notifier).applyFromRegistration(
          countryCode: countryCode,
          mode: mode,
          usdToLocalRate: double.tryParse(_rateCtrl.text.trim()),
        );
    ref.read(authProvider.notifier).login(
      userName: _nameCtrl.text.isEmpty ? 'Gérant' : _nameCtrl.text,
      businessName: _bizNameCtrl.text.isEmpty ? 'Mon commerce' : _bizNameCtrl.text,
      module: ActiveModule.retail,
    );
    setState(() => _isLoading = false);
    context.go(AppRoutes.pin);
  }

  void _onBack() {
    if (_currentStep == 0) {
      if (_emailSubStep == 1) {
        setState(() {
          _emailSubStep = 0;
          _codeCtrl.clear();
          _codeError = '';
        });
      }
      return;
    }
    if (_currentStep == 1) {
      // Return to code entry (email was already verified/sent)
      setState(() {
        _currentStep = 0;
        _emailSubStep = _codeSent ? 1 : 0;
      });
      return;
    }
    setState(() => _currentStep--);
  }

  bool get _canGoBack =>
      !(_currentStep == 0 && _emailSubStep == 0);

  String get _nextLabel {
    if (_currentStep == _totalSteps - 1) return 'Créer un compte';
    if (_currentStep == 0 && _emailSubStep == 0) return 'Envoyer le code';
    if (_currentStep == 0 && _emailSubStep == 1) return 'Vérifier et continuer';
    return 'Continuer';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 520 : double.infinity),
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
                    _Header(
                      currentStep: _currentStep,
                      totalSteps: _totalSteps,
                      canGoBack: _canGoBack,
                      onBack: _onBack,
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    AnimatedSwitcher(
                      duration: AppConstants.animNormal,
                      child: _buildStep(_currentStep),
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    AppButton(
                      label: _nextLabel,
                      onPressed: _onNext,
                      isLoading: _isLoading,
                    ),
                    if (_currentStep == 0 && _emailSubStep == 0) ...[
                      const SizedBox(height: AppConstants.spacing12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Vous avez déjà un compte ? ',
                              style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray)),
                          TextButton(
                            onPressed: () => context.go(AppRoutes.login),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Se connecter',
                                style: AppTextStyles.body(
                                        color: isDark
                                            ? AppColors.skyBlue
                                            : AppColors.primaryBlue)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _emailSubStep == 0
            ? _StepEmailEntry(
                key: const ValueKey('email_entry'),
                emailCtrl: _emailCtrl,
                emailError: _emailError.isEmpty ? null : _emailError,
                onChanged: (_) => setState(() => _emailError = ''),
              )
            : _StepEmailCode(
                key: const ValueKey('email_code'),
                email: _emailCtrl.text.trim(),
                codeCtrl: _codeCtrl,
                codeError: _codeError.isEmpty ? null : _codeError,
                onChanged: (_) => setState(() => _codeError = ''),
                onChangeEmail: () => setState(() {
                  _emailSubStep = 0;
                  _codeCtrl.clear();
                  _codeError = '';
                }),
                onResend: () async {
                  setState(() => _isLoading = true);
                  await Future.delayed(const Duration(milliseconds: 600));
                  if (!mounted) return;
                  setState(() => _isLoading = false);
                  _snack('Code renvoyé à ${_emailCtrl.text.trim()}. (Démo : 123456)');
                },
              );
      case 1:
        return _Step1ContactInfo(
          key: const ValueKey(1),
          nameCtrl: _nameCtrl,
          phoneCtrl: _phoneCtrl,
          nameError: _nameError.isEmpty ? null : _nameError,
          onNameChanged: (_) => setState(() => _nameError = ''),
        );
      case 2:
        return _Step2BusinessDetails(
          key: const ValueKey(2),
          bizNameCtrl: _bizNameCtrl,
          bizNameError: _bizNameError.isEmpty ? null : _bizNameError,
          onBizNameChanged: (_) => setState(() => _bizNameError = ''),
        );
      case 3:
        return _Step3BusinessAddress(
          key: const ValueKey(3),
          addressCtrl: _addressCtrl,
          cityCtrl: _cityCtrl,
          selectedDepartment: _selectedDepartment,
          onDepartmentChanged: (v) => setState(() {
            _selectedDepartment = v;
            _departmentError = '';
          }),
          zipCtrl: _zipCtrl,
          addressError: _addressError.isEmpty ? null : _addressError,
          cityError: _cityError.isEmpty ? null : _cityError,
          departmentError: _departmentError.isEmpty ? null : _departmentError,
          onAddressChanged: (_) => setState(() => _addressError = ''),
          onCityChanged: (_) => setState(() => _cityError = ''),
        );
      case 4:
        return _Step4ModuleSelection(
          key: const ValueKey(4),
          selected: _selectedModule,
          onSelected: (m) => setState(() {
            _selectedModule = m;
            _moduleError = '';
          }),
          moduleError: _moduleError.isEmpty ? null : _moduleError,
        );
      case 5:
        return _Step5Currency(
          key: const ValueKey(5),
          selected: _currency,
          onChanged: (v) => setState(() => _currency = v),
          rateCtrl: _rateCtrl,
        );
      case 6:
        return _Step6Language(
          key: const ValueKey(6),
          selected: _language,
          onChanged: (v) => setState(() => _language = v),
        );
      case 7:
        return _Step7Password(
          key: const ValueKey(7),
          passwordCtrl: _passwordCtrl,
          confirmCtrl: _confirmCtrl,
          termsAccepted: _termsAccepted,
          onTermsChanged: (v) => setState(() {
            _termsAccepted = v;
            if (v) _termsError = '';
          }),
          passwordError: _passwordError.isEmpty ? null : _passwordError,
          confirmError: _confirmError.isEmpty ? null : _confirmError,
          termsError: _termsError.isEmpty ? null : _termsError,
          onPasswordChanged: (_) => setState(() => _passwordError = ''),
          onConfirmChanged: (_) => setState(() => _confirmError = ''),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Shared header + progress ──────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final bool canGoBack;
  final VoidCallback onBack;
  final bool isDark;

  const _Header({
    required this.currentStep,
    required this.totalSteps,
    required this.canGoBack,
    required this.onBack,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (canGoBack)
              GestureDetector(
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_back_ios_rounded,
                      size: 18,
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                ),
              ),
            Expanded(
              child: Text(
                'Créer un compte',
                style: AppTextStyles.h2(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
              ),
            ),
            Text('${currentStep + 1} / $totalSteps',
                style: AppTextStyles.caption()),
          ],
        ),
        const SizedBox(height: AppConstants.spacing16),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (currentStep + 1) / totalSteps,
            backgroundColor:
                isDark ? AppColors.darkBorder : const Color(0xFFE8F0F8),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.amber),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

// ── Step 0a — Email Entry ─────────────────────────────────────────────────────

class _StepEmailEntry extends StatelessWidget {
  final TextEditingController emailCtrl;
  final String? emailError;
  final ValueChanged<String>? onChanged;

  const _StepEmailEntry({
    super.key,
    required this.emailCtrl,
    this.emailError,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vérifiez votre e-mail', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text(
          'Enter your email address and we\'ll send you a verification code to get started.',
          style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
        const SizedBox(height: AppConstants.spacing24),
        AppInput(
          label: 'Adresse e-mail',
          hint: 'manager@business.ht',
          controller: emailCtrl,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: InputFormatters.email,
          errorText: emailError,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Step 0b — Code Entry ──────────────────────────────────────────────────────

class _StepEmailCode extends StatelessWidget {
  final String email;
  final TextEditingController codeCtrl;
  final String? codeError;
  final ValueChanged<String>? onChanged;
  final VoidCallback onChangeEmail;
  final VoidCallback onResend;

  const _StepEmailCode({
    super.key,
    required this.email,
    required this.codeCtrl,
    required this.codeError,
    required this.onChangeEmail,
    required this.onResend,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saisir le code de vérification', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        RichText(
          text: TextSpan(
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray),
            children: [
              const TextSpan(text: 'A 6-digit code was sent to '),
              TextSpan(
                  text: email,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing24),
        AppInput(
          label: 'Code de vérification',
          hint: 'Code à 6 chiffres',
          controller: codeCtrl,
          prefixIcon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          errorText: codeError,
          onChanged: onChanged,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        const SizedBox(height: AppConstants.spacing16),
        Row(
          children: [
            TextButton.icon(
              onPressed: onResend,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Renvoyer le code'),
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onChangeEmail,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Changer l\'e-mail'),
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? AppColors.coolGray : AppColors.darkGray,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Step 1 — Contact Info ─────────────────────────────────────────────────────

class _Step1ContactInfo extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final String? nameError;
  final ValueChanged<String>? onNameChanged;

  const _Step1ContactInfo({
    super.key,
    required this.nameCtrl,
    required this.phoneCtrl,
    this.nameError,
    this.onNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vos informations', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Parlez-nous du propriétaire.',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing24),
        AppInput(
            label: 'Nom complet',
            hint: 'e.g. Jean-Marc Dupont',
            controller: nameCtrl,
            prefixIcon: Icons.person_outline,
            errorText: nameError,
            onChanged: onNameChanged),
        const SizedBox(height: AppConstants.spacing16),
        AppInput(
            label: 'Numéro de téléphone',
            hint: '+509 3XXX-XXXX',
            controller: phoneCtrl,
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            inputFormatters: InputFormatters.phone),
      ],
    );
  }
}

// ── Step 2 — Business Details ─────────────────────────────────────────────────

class _Step2BusinessDetails extends StatelessWidget {
  final TextEditingController bizNameCtrl;
  final String? bizNameError;
  final ValueChanged<String>? onBizNameChanged;

  const _Step2BusinessDetails({
    super.key,
    required this.bizNameCtrl,
    this.bizNameError,
    this.onBizNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Détails du commerce', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Parlez-nous de votre commerce.',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing24),
        AppInput(
            label: 'Nom du commerce',
            hint: 'e.g. Hôtel Karibe',
            controller: bizNameCtrl,
            prefixIcon: Icons.business_outlined,
            errorText: bizNameError,
            onChanged: onBizNameChanged),
      ],
    );
  }
}

// ── Step 3 — Business Address ─────────────────────────────────────────────────

class _Step3BusinessAddress extends StatelessWidget {
  final TextEditingController addressCtrl;
  final TextEditingController cityCtrl;
  final String? selectedDepartment;
  final ValueChanged<String?> onDepartmentChanged;
  final TextEditingController zipCtrl;
  final String? addressError;
  final String? cityError;
  final String? departmentError;
  final ValueChanged<String>? onAddressChanged;
  final ValueChanged<String>? onCityChanged;

  const _Step3BusinessAddress({
    super.key,
    required this.addressCtrl,
    required this.cityCtrl,
    required this.selectedDepartment,
    required this.onDepartmentChanged,
    required this.zipCtrl,
    this.addressError,
    this.cityError,
    this.departmentError,
    this.onAddressChanged,
    this.onCityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Adresse du commerce', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Où se trouve votre commerce ?',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing24),

        // Country — locked to Haiti for now
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.5)
                : const Color(0xFFF5F5F5),
            borderRadius:
                BorderRadius.circular(AppConstants.radiusInput),
            border: Border.all(
                color:
                    isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
          ),
          child: Row(
            children: [
              Icon(Icons.flag_outlined,
                  size: 20,
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pays',
                        style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray)),
                    const SizedBox(height: 2),
                    Text(
                      'Haïti',
                      style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.lock_outline,
                  size: 16,
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text('D\'autres pays arrivent bientôt.',
            style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing16),

        AppInput(
          label: 'Adresse',
          hint: 'e.g. 12 Rue Lamarre',
          controller: addressCtrl,
          prefixIcon: Icons.home_outlined,
          maxLines: 2,
          errorText: addressError,
          onChanged: onAddressChanged,
        ),
        const SizedBox(height: AppConstants.spacing16),
        AppInput(
          label: 'Ville',
          hint: 'e.g. Port-au-Prince',
          controller: cityCtrl,
          prefixIcon: Icons.location_city_outlined,
          errorText: cityError,
          onChanged: onCityChanged,
        ),
        const SizedBox(height: AppConstants.spacing16),
        DropdownButtonFormField<String>(
          value: selectedDepartment,
          decoration: InputDecoration(
            labelText: 'Département / région',
            prefixIcon: const Icon(Icons.map_outlined),
            border: baseBorder,
            enabledBorder: baseBorder,
            focusedBorder: focusBorder,
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              borderSide: const BorderSide(color: AppColors.boldRed, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              borderSide: const BorderSide(color: AppColors.boldRed, width: 2),
            ),
            errorText: departmentError,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          hint: Text('Choisir le service',
              style: AppTextStyles.body(
                  color:
                      isDark ? AppColors.coolGray : AppColors.darkGray)),
          items: _haitiDepartments
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: onDepartmentChanged,
        ),
        const SizedBox(height: AppConstants.spacing16),
        AppInput(
          label: 'Code postal (facultatif)',
          hint: 'e.g. HT6120',
          controller: zipCtrl,
          prefixIcon: Icons.local_post_office_outlined,
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text(
          'Le code postal est facultatif — la plupart des adresses en Haïti n\'en ont pas.',
          style: AppTextStyles.caption(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
      ],
    );
  }
}

// ── Step 4 — Module Selection ─────────────────────────────────────────────────

class _Step4ModuleSelection extends StatelessWidget {
  final ActiveModule? selected;
  final ValueChanged<ActiveModule> onSelected;
  final String? moduleError;

  const _Step4ModuleSelection({
    super.key,
    required this.selected,
    required this.onSelected,
    this.moduleError,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choisissez votre module', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Choisissez le type de commerce que vous gérez.',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        if (moduleError != null) ...[
          const SizedBox(height: AppConstants.spacing12),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 14, color: AppColors.boldRed),
              const SizedBox(width: 6),
              Text(moduleError!,
                  style: AppTextStyles.caption(color: AppColors.boldRed)),
            ],
          ),
        ],
        const SizedBox(height: AppConstants.spacing24),
        _ModuleCard(
          module: ActiveModule.hotel,
          icon: Icons.hotel_rounded,
          title: 'Hôtel + restaurant',
          description:
              'Gestion hôtelière complète (chambres, réservations, arrivées et départs, ménage) avec un restaurant intégré — tables, menu, cuisine, service en chambre et facture unique au départ.',
          isSelected: selected == ActiveModule.hotel,
          onTap: () => onSelected(ActiveModule.hotel),
          badge: 'MOST POPULAR',
        ),
        const SizedBox(height: AppConstants.spacing12),
        _ModuleCard(
          module: ActiveModule.restaurant,
          icon: Icons.restaurant_rounded,
          title: 'Restaurant',
          description:
              'Restaurant indépendant avec tables, menu, commandes, écran cuisine et facturation. Sans fonctions hôtel.',
          isSelected: selected == ActiveModule.restaurant,
          onTap: () => onSelected(ActiveModule.restaurant),
        ),
        const SizedBox(height: AppConstants.spacing12),
        _ModuleCard(
          module: ActiveModule.retail,
          icon: Icons.shopping_cart_rounded,
          title: 'Détail / boutique',
          description:
              'Caisse, inventaire, fournisseurs, crédit client et rapports.',
          isSelected: selected == ActiveModule.retail,
          onTap: () => onSelected(ActiveModule.retail),
        ),
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final ActiveModule module;
  final IconData icon;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  const _ModuleCard({
    required this.module,
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animNormal,
        padding: const EdgeInsets.all(AppConstants.spacing16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.2)
                  : AppColors.lightBlue)
              : (isDark ? AppColors.darkSurface : AppColors.warmOffWhite),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(
            color:
                isSelected ? AppColors.primaryBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryBlue
                    : AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: isSelected
                      ? AppColors.white
                      : AppColors.primaryBlue,
                  size: 26),
            ),
            const SizedBox(width: AppConstants.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: AppTextStyles.h3(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack)),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(badge!,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.nearBlack,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: AppConstants.animFast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primaryBlue
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryBlue
                      : AppColors.darkGray,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 5 — Currency (country locked to Haiti) ───────────────────────────────

class _Step5Currency extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final TextEditingController rateCtrl;

  const _Step5Currency({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.rateCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paramètres de devise', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text(
          'La devise locale suit votre pays. Le USD sert de référence et pour les paiements par carte.',
          style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
        const SizedBox(height: AppConstants.spacing16),

        // Country display — locked from address step
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : AppColors.lightBlue,
            borderRadius:
                BorderRadius.circular(AppConstants.radiusInput),
            border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pays : Haïti · Devise locale : HTG (gourde haïtienne)',
                  style:
                      AppTextStyles.caption(color: AppColors.primaryBlue),
                ),
              ),
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.primaryBlue),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing16),

        AppInput(
          label: 'Taux de change (1 USD = ? HTG)',
          hint: 'e.g. 135',
          controller: rateCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: InputFormatters.decimalAmount,
          prefixIcon: Icons.currency_exchange,
        ),
        const SizedBox(height: AppConstants.spacing16),

        Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(
              'Tarification avancée (facultatif)',
              style: AppTextStyles.body().copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ),
            ),
            subtitle: Text(
              'Changez seulement si votre commerce n\'utilise pas la valeur par défaut.',
              style: AppTextStyles.caption(
                  color:
                      isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            children: [
              _SelectOption(
                value: 'both',
                label: 'Local + référence USD (recommandé)',
                subtitle:
                    'Par défaut : prix en HTG. Les totaux affichent aussi l\'équivalent en USD. À l\'encaissement, le personnel peut saisir des espèces en HTG ou en USD avec le taux ci-dessous.',
                selected: selected,
                onChanged: onChanged,
              ),
              const SizedBox(height: AppConstants.spacing12),
              _SelectOption(
                value: 'htg',
                label: 'Devise locale seulement',
                subtitle: 'Prix et espèces en HTG',
                selected: selected,
                onChanged: onChanged,
              ),
              const SizedBox(height: AppConstants.spacing12),
              _SelectOption(
                value: 'usd',
                label: 'USD seulement',
                subtitle: 'Prix et espèces en dollars',
                selected: selected,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 6 — Language ─────────────────────────────────────────────────────────

class _Step6Language extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _Step6Language(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Langue préférée', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Choisissez la langue de l\'application pour votre équipe.',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing24),
        _SelectOption(
            value: 'kr',
            label: 'Kreyòl Ayisyen',
            subtitle: 'Créole haïtien — langue principale',
            selected: selected,
            onChanged: onChanged),
        const SizedBox(height: AppConstants.spacing12),
        _SelectOption(
            value: 'fr',
            label: 'Français',
            subtitle: 'Français — pour les documents officiels',
            selected: selected,
            onChanged: onChanged),
        const SizedBox(height: AppConstants.spacing12),
        _SelectOption(
            value: 'en',
            label: 'Anglais',
            subtitle: 'Anglais — pour les clients internationaux',
            selected: selected,
            onChanged: onChanged),
      ],
    );
  }
}

// ── Step 7 — Password + T&C ───────────────────────────────────────────────────

class _Step7Password extends StatelessWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool termsAccepted;
  final ValueChanged<bool> onTermsChanged;
  final String? passwordError;
  final String? confirmError;
  final String? termsError;
  final ValueChanged<String>? onPasswordChanged;
  final ValueChanged<String>? onConfirmChanged;

  const _Step7Password({
    super.key,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.termsAccepted,
    required this.onTermsChanged,
    this.passwordError,
    this.confirmError,
    this.termsError,
    this.onPasswordChanged,
    this.onConfirmChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Créer un mot de passe', style: AppTextStyles.h2()),
        const SizedBox(height: AppConstants.spacing4),
        Text('Ce sera votre mot de passe administrateur. Partagez-le avec prudence.',
            style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        const SizedBox(height: AppConstants.spacing24),
        AppInput(
            label: 'Mot de passe',
            hint: 'Au moins 8 caractères',
            controller: passwordCtrl,
            obscureText: true,
            showToggleObscure: true,
            prefixIcon: Icons.lock_outline,
            errorText: passwordError,
            onChanged: onPasswordChanged),
        const SizedBox(height: AppConstants.spacing16),
        AppInput(
            label: 'Confirmer le mot de passe',
            hint: 'Répétez le mot de passe',
            controller: confirmCtrl,
            obscureText: true,
            showToggleObscure: true,
            prefixIcon: Icons.lock_outline,
            errorText: confirmError,
            onChanged: onConfirmChanged),
        const SizedBox(height: AppConstants.spacing24),

        // Terms & Conditions
        GestureDetector(
          onTap: () => onTermsChanged(!termsAccepted),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: AppConstants.animFast,
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: termsAccepted
                      ? AppColors.primaryBlue
                      : Colors.transparent,
                  border: Border.all(
                    color: termsAccepted
                        ? AppColors.primaryBlue
                        : (isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray),
                    width: 2,
                  ),
                ),
                child: termsAccepted
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTextStyles.body(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray),
                    children: [
                      const TextSpan(text: 'J\'accepte les '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            // TODO: open terms URL
                          },
                          child: Text(
                            'Conditions générales',
                            style: AppTextStyles.body(
                                    color: isDark
                                        ? AppColors.skyBlue
                                        : AppColors.primaryBlue)
                                .copyWith(
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const TextSpan(
                          text:
                              ' et la politique de confidentialité de BizManager Haïti.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (termsError != null) ...[
          const SizedBox(height: AppConstants.spacing8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 34),
              const Icon(Icons.error_outline, size: 14, color: AppColors.boldRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(termsError!,
                    style: AppTextStyles.caption(color: AppColors.boldRed)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppConstants.spacing16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.lightBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 16, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Votre commerce sera prêt juste après cette étape. Le personnel s\'ajoute dans Paramètres.',
                  style:
                      AppTextStyles.caption(color: AppColors.primaryBlue),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared radio-style option ─────────────────────────────────────────────────

class _SelectOption extends StatelessWidget {
  final String value;
  final String label;
  final String subtitle;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SelectOption({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: AppConstants.animNormal,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : (isDark
                    ? AppColors.darkBorder
                    : const Color(0xFFE0E0E0)),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? (isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.15)
                  : AppColors.lightBlue)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack)
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: AppTextStyles.caption()),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: selected,
              onChanged: (v) => onChanged(v!),
              activeColor: AppColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

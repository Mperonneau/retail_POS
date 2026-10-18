import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff_directory_entry.dart';
import '../../core/models/staff_role.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/staff_directory_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';

/// Add or edit staff: name, email, phone (required), role, 4-digit PIN, active.
class StaffEditorSheet extends ConsumerStatefulWidget {
  const StaffEditorSheet({
    super.key,
    required this.isDark,
    this.existing,
  });

  final bool isDark;
  final StaffDirectoryEntry? existing;

  @override
  ConsumerState<StaffEditorSheet> createState() => _StaffEditorSheetState();
}

class _StaffEditorSheetState extends ConsumerState<StaffEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;

  late StaffRole _role;
  late bool _isActive;

  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _pinError;
  String? _confirmError;

  static final _pinFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(4),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.fullName ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _pinCtrl = TextEditingController();
    _pinConfirmCtrl = TextEditingController();
    final module = ref.read(authProvider).module;
    _role = e?.role ??
        (module == ActiveModule.retail ? StaffRole.seller : StaffRole.waiter);
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(t);
  }

  void _save() {
    setState(() {
      _nameError = null;
      _emailError = null;
      _phoneError = null;
      _pinError = null;
      _confirmError = null;
    });

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final pinConfirm = _pinConfirmCtrl.text.trim();

    final dir = ref.read(staffDirectoryProvider.notifier);
    final existing = widget.existing;

    if (name.isEmpty) {
      setState(() => _nameError = 'Le nom est obligatoire.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Saisissez un e-mail valide.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _phoneError = 'Le numéro de téléphone est obligatoire.');
      return;
    }
    if (dir.isPhoneTaken(phone, excludeId: existing?.id)) {
      setState(() => _phoneError = 'Ce téléphone est déjà utilisé par un autre employé.');
      return;
    }

    String pinToStore;
    if (existing == null) {
      if (pin.length != 4) {
        setState(() => _pinError = 'Définissez un code PIN à 4 chiffres.');
        return;
      }
      if (pin != pinConfirm) {
        setState(() => _confirmError = 'Les codes PIN ne correspondent pas.');
        return;
      }
      if (dir.isPinTaken(pin)) {
        setState(() => _pinError = 'Ce code PIN est déjà attribué.');
        return;
      }
      pinToStore = pin;
    } else {
      if (pin.isEmpty && pinConfirm.isEmpty) {
        pinToStore = existing.pinDigits;
      } else {
        if (pin.length != 4) {
          setState(() => _pinError = 'Le PIN doit avoir 4 chiffres, ou laissez les deux champs vides.');
          return;
        }
        if (pin != pinConfirm) {
          setState(() => _confirmError = 'Les codes PIN ne correspondent pas.');
          return;
        }
        if (dir.isPinTaken(pin, excludeId: existing.id)) {
          setState(() => _pinError = 'Ce code PIN est déjà attribué.');
          return;
        }
        pinToStore = pin;
      }
    }

    if (existing == null) {
      dir.add(
        StaffDirectoryEntry(
          id: 'emp_${DateTime.now().millisecondsSinceEpoch}',
          fullName: name,
          email: email,
          phone: phone,
          role: _role,
          pinDigits: pinToStore,
          isActive: _isActive,
        ),
      );
    } else {
      dir.update(
        existing.copyWith(
          fullName: name,
          email: email,
          phone: phone,
          role: _role,
          pinDigits: pinToStore,
          isActive: _isActive,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        top: AppConstants.spacing24,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Modifier l\'employé' : 'Ajouter un employé',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Le téléphone est obligatoire. Le code PIN sert à ouvrir la caisse partagée.',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nom complet',
                errorText: _nameError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: 'E-mail',
                errorText: _emailError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              inputFormatters: InputFormatters.email,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: 'Téléphone *',
                errorText: _phoneError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: InputFormatters.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            DropdownButtonFormField<StaffRole>(
              value: _role,
              decoration: InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              items: () {
                final module = ref.watch(authProvider.select((a) => a.module));
                final roles = [...staffRolesForModule(module)];
                if (!roles.contains(_role)) roles.add(_role);
                return roles
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(staffRoleDisplayLabel(r)),
                      ),
                    )
                    .toList();
              }(),
              onChanged: (v) {
                if (v != null) setState(() => _role = v);
              },
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: _pinCtrl,
              decoration: InputDecoration(
                labelText: isEdit ? 'Nouveau PIN (facultatif)' : 'PIN (4 chiffres) *',
                hintText: '0000',
                errorText: _pinError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: _pinFormatters,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: _pinConfirmCtrl,
              decoration: InputDecoration(
                labelText: isEdit ? 'Confirmer le nouveau PIN' : 'Confirmer le PIN *',
                errorText: _confirmError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: _pinFormatters,
              textInputAction: TextInputAction.done,
              onEditingComplete: _save,
            ),
            if (isEdit) ...[
              const SizedBox(height: AppConstants.spacing8),
              Text(
                'Laissez les champs PIN vides pour garder le code actuel.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacing12),
            SwitchListTile(
              title: Text('Actif', style: AppTextStyles.body()),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: AppColors.primaryBlue,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppConstants.spacing16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                    ),
                    child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

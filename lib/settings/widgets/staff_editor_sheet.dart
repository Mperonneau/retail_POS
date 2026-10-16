import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff_directory_entry.dart';
import '../../core/models/staff_role.dart';
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
    _role = e?.role ?? StaffRole.waiter;
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
      setState(() => _nameError = 'Name is required.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Enter a valid email.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _phoneError = 'Phone number is required.');
      return;
    }
    if (dir.isPhoneTaken(phone, excludeId: existing?.id)) {
      setState(() => _phoneError = 'This phone is already used by another staff member.');
      return;
    }

    String pinToStore;
    if (existing == null) {
      if (pin.length != 4) {
        setState(() => _pinError = 'Set a 4-digit PIN.');
        return;
      }
      if (pin != pinConfirm) {
        setState(() => _confirmError = 'PINs do not match.');
        return;
      }
      if (dir.isPinTaken(pin)) {
        setState(() => _pinError = 'This PIN is already assigned.');
        return;
      }
      pinToStore = pin;
    } else {
      if (pin.isEmpty && pinConfirm.isEmpty) {
        pinToStore = existing.pinDigits;
      } else {
        if (pin.length != 4) {
          setState(() => _pinError = 'PIN must be 4 digits or leave both fields blank.');
          return;
        }
        if (pin != pinConfirm) {
          setState(() => _confirmError = 'PINs do not match.');
          return;
        }
        if (dir.isPinTaken(pin, excludeId: existing.id)) {
          setState(() => _pinError = 'This PIN is already assigned.');
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
              isEdit ? 'Edit Staff Member' : 'Add Staff Member',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Phone is required. PIN is used on the shared device login screen.',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Full name',
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
                labelText: 'Email',
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
                labelText: 'Phone number *',
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
              items: StaffRole.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(staffRoleDisplayLabel(r)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _role = v);
              },
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: _pinCtrl,
              decoration: InputDecoration(
                labelText: isEdit ? 'New PIN (optional)' : 'PIN (4 digits) *',
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
                labelText: isEdit ? 'Confirm new PIN' : 'Confirm PIN *',
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
                'Leave PIN fields blank to keep the current PIN.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacing12),
            SwitchListTile(
              title: Text('Active', style: AppTextStyles.body()),
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
                    child: const Text('Cancel'),
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
                    child: Text(isEdit ? 'Save' : 'Add'),
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

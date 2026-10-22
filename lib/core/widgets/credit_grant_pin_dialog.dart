import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/client_credit_grant.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_settings_provider.dart';
import '../providers/staff_directory_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Asks for the PIN of someone allowed to put a balance on a client account.
/// Returns that person's name, or null when the cashier cancels.
Future<String?> showCreditGrantPinDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool isDark,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CreditGrantPinDialog(isDark: isDark),
  );
}

class _CreditGrantPinDialog extends ConsumerStatefulWidget {
  final bool isDark;

  const _CreditGrantPinDialog({required this.isDark});

  @override
  ConsumerState<_CreditGrantPinDialog> createState() =>
      _CreditGrantPinDialogState();
}

class _CreditGrantPinDialogState extends ConsumerState<_CreditGrantPinDialog> {
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final staff = lookupStaffByPin(
      _pinCtrl.text,
      ref.read(staffDirectoryProvider),
    );
    if (staff == null) {
      setState(() => _error = 'Code PIN invalide.');
      return;
    }
    final allowed = employeeCanGrantClientCredit(
      employeeId: staff.employeeId,
      role: staff.role,
      module: ref.read(authProvider).module,
      settings: ref.read(permissionSettingsProvider),
    );
    if (!allowed) {
      setState(() => _error = 'Cette personne ne peut pas accorder un crédit.');
      return;
    }
    Navigator.of(context).pop(staff.name);
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark ? AppColors.coolGray : AppColors.darkGray;
    return AlertDialog(
      title: const Text('Autorisation'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Un code PIN autorisé est nécessaire pour enregistrer le solde au compte du client.',
              style: AppTextStyles.body(color: muted),
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              key: const Key('credit-grant-pin'),
              controller: _pinCtrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Code PIN',
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Autoriser')),
      ],
    );
  }
}

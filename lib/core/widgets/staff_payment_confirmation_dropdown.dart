import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'discount_approval_dialog.dart';

/// Staff register confirmation for payment-link table orders (NOT PAID / PAID).
///
/// When [adminAuthOrderLabel] is non-null, switching to **PAID** runs the same
/// admin code flow as "Marquer payé" on the payment-link status sheet.
class StaffPaymentConfirmationDropdown extends ConsumerWidget {
  final bool isDark;
  final bool staffPaid;
  final ValueChanged<bool> onChanged;
  final bool compact;
  /// e.g. `Order #101`. When set, marking register **PAID** requires admin approval.
  final String? adminAuthOrderLabel;

  const StaffPaymentConfirmationDropdown({
    super.key,
    required this.isDark,
    required this.staffPaid,
    required this.onChanged,
    this.compact = false,
    this.adminAuthOrderLabel,
  });

  Future<void> _applyChange(
    BuildContext context,
    WidgetRef ref,
    bool newPaid,
  ) async {
    if (newPaid && adminAuthOrderLabel != null) {
      final approved = await showAdminApprovalDialog(
        context,
        ref,
        message:
            'Cette action exige une autorisation admin. Ne marquez '
            '$adminAuthOrderLabel comme payé que si vous pouvez confirmer que '
            'le paiement a bien été reçu hors de l\'application.',
        isDark: isDark,
        title: 'Autorisation admin',
        codeFieldLabel: 'Mot de passe ou code admin',
        confirmButtonLabel: 'Autoriser',
      );
      if (approved == true && context.mounted) onChanged(newPaid);
    } else {
      onChanged(newPaid);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final border =
        isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Caisse',
          style: AppTextStyles.caption(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ).copyWith(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 8 : 9,
          ),
        ),
        SizedBox(width: compact ? 4 : 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(6),
            color: isDark ? AppColors.darkBackground : const Color(0xFFF7F7F7),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<bool>(
              value: staffPaid,
              isDense: true,
              borderRadius: BorderRadius.circular(8),
              iconSize: compact ? 16 : 18,
              style: AppTextStyles.caption(color: fg).copyWith(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 9 : 10,
              ),
              items: const [
                DropdownMenuItem(value: false, child: Text('NON PAYÉ')),
                DropdownMenuItem(value: true, child: Text('PAYÉ')),
              ],
              onChanged: (v) {
                if (v == null || v == staffPaid) return;
                _applyChange(context, ref, v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tax_settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Shows a dialog requiring admin code to approve a sensitive action.
/// [message] is shown to the user. Uses the same code as discount approval (Settings).
/// [codeFieldLabel] and [confirmButtonLabel] customize the input hint and primary action.
/// Returns true if approved, false if cancelled, null if dismissed.
/// If [ref]'s discountApprovalCodeProvider is empty, returns true without showing dialog.
Future<bool?> showAdminApprovalDialog(
  BuildContext context,
  WidgetRef ref, {
  required String message,
  required bool isDark,
  String title = 'Admin approval',
  String codeFieldLabel = 'Password / code',
  String confirmButtonLabel = 'Approve',
}) async {
  final code = ref.read(discountApprovalCodeProvider);
  if (code.isEmpty) return true;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final ctrl = TextEditingController();
      String? error;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenW = MediaQuery.sizeOf(ctx).width;
          final contentW =
              (screenW - 48).clamp(260.0, 320.0); // narrow dialog on web/desktop
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            title: Text(title),
            content: SizedBox(
              width: contentW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: codeFieldLabel,
                      errorText: error,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                      ),
                    ),
                    onChanged: (_) {
                      if (error != null) setDialogState(() => error = null);
                    },
                    onSubmitted: (v) {
                      if (v.trim() == code) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDialogState(() => error = 'Incorrect code');
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (ctrl.text.trim() == code) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() => error = 'Incorrect code');
                  }
                },
                child: Text(confirmButtonLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Shows a dialog requiring admin code to approve applying [percent]% discount.
/// Returns true if approved, false if cancelled, null if dismissed.
/// Use when the user selects a discount rate > 0% in any module (Restaurant, Hotel, Retail).
Future<bool?> showDiscountApprovalDialog(
  BuildContext context,
  WidgetRef ref, {
  required double percent,
  required bool isDark,
}) async {
  final code = ref.read(discountApprovalCodeProvider);
  if (code.isEmpty) return true;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final ctrl = TextEditingController();
      String? error;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenW = MediaQuery.sizeOf(ctx).width;
          final contentW = (screenW - 48).clamp(260.0, 320.0);
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            title: const Text('Approve discount'),
            content: SizedBox(
              width: contentW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter admin password or code to apply ${percent.toInt()}% discount.',
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password / code',
                      errorText: error,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                      ),
                    ),
                    onChanged: (_) {
                      if (error != null) setDialogState(() => error = null);
                    },
                    onSubmitted: (v) {
                      if (v.trim() == code) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDialogState(() => error = 'Incorrect code');
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (ctrl.text.trim() == code) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() => error = 'Incorrect code');
                  }
                },
                child: const Text('Approve'),
              ),
            ],
          );
        },
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Inline validation error displayed below a form field.
/// Renders nothing when [text] is null or empty.
class FormFieldError extends StatelessWidget {
  final String? text;

  const FormFieldError({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text!,
        style: const TextStyle(
          color: AppColors.boldRed,
          fontSize: 12,
        ),
      ),
    );
  }
}

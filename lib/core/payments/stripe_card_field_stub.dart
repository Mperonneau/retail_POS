import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'stripe_card_controller.dart';

/// Non-web stand-in. Card entry runs in the browser register.
class StripeCardField extends StatelessWidget {
  const StripeCardField({
    super.key,
    required this.publishableKey,
    required this.controller,
    required this.isDark,
    this.onReady,
    this.onError,
  });

  final String publishableKey;
  final StripeCardController controller;
  final bool isDark;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) {
    return Text(
      'La saisie de carte est disponible sur la caisse web.',
      style: AppTextStyles.body(
        color: isDark ? AppColors.coolGray : AppColors.darkGray,
      ),
    );
  }
}

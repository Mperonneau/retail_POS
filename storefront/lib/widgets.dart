import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:retail_pos/core/widgets/app_button.dart';

import 'money.dart';

const double kPhoneMaxWidth = 560;

/// US dollars first (dominant), gourdes underneath.
class DualPrice extends StatelessWidget {
  const DualPrice({
    super.key,
    required this.htg,
    required this.rate,
    this.large = false,
    this.regularHtg = 0,
    this.alignEnd = false,
  });

  final double htg;
  final double rate;
  final bool large;
  final double regularHtg;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              Money.usdFromHtg(htg, rate),
              style: AppTextStyles.price(color: AppColors.nearBlack)
                  .copyWith(fontSize: large ? 24 : 15, height: 1.2),
            ),
            if (regularHtg > htg)
              Text(
                Money.usdFromHtg(regularHtg, rate),
                style: AppTextStyles.caption(color: AppColors.darkGray).copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
          ],
        ),
        Text(
          Money.htg(htg),
          style: AppTextStyles.caption(color: AppColors.darkGray)
              .copyWith(fontSize: large ? 13 : 11.5),
        ),
      ],
    );
  }
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({super.key, required this.url, required this.name, this.radius = 0});

  final String url;
  final String name;
  final double radius;

  static const _tints = [
    Color(0xFFE8F0F8),
    Color(0xFFFFF3DC),
    Color(0xFFE6F4EA),
    Color(0xFFF3E8F8),
    Color(0xFFFDE8E8),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[name.hashCode.abs() % _tints.length];
    final placeholder = Container(
      color: tint,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: AppTextStyles.h1(color: AppColors.primaryBlue.withValues(alpha: 0.55))
            .copyWith(fontSize: 34),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : Container(color: tint),
            ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.caption(color: color)
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppConstants.spacing16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard + 4),
        border: Border.all(color: const Color(0xFFECEAE4)),
      ),
      child: child,
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 3));
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacing24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: AppColors.primaryBlue),
              ),
              const SizedBox(height: AppConstants.spacing16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h2(color: AppColors.nearBlack)),
              const SizedBox(height: AppConstants.spacing8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(color: AppColors.darkGray)),
              if (actionLabel != null) ...[
                const SizedBox(height: AppConstants.spacing20),
                AppButton(label: actionLabel!, onPressed: onAction, fullWidth: false, width: 200),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before wiping every line. Returns true when the shopper confirms.
Future<bool> confirmClearCart(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Vider le panier ?', style: AppTextStyles.h2(color: AppColors.nearBlack)),
      content: Text(
        'Tous les articles seront retirés.',
        style: AppTextStyles.body(color: AppColors.darkGray),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.boldRed),
          child: const Text('Vider'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Tap-to-change quantity control.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.compact = false,
  });

  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 40.0;
    Widget button(IconData icon, VoidCallback? onTap) => SizedBox(
          width: size,
          height: size,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            icon: Icon(icon, size: compact ? 16 : 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.lightBlue,
              foregroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFF0F0F0),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove_rounded, onMinus),
        SizedBox(
          width: compact ? 30 : 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTextStyles.price(color: AppColors.nearBlack)
                .copyWith(fontSize: compact ? 14 : 16),
          ),
        ),
        button(Icons.add_rounded, onPlus),
      ],
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.boldRed : AppColors.nearBlack,
      width: 420,
    ));
}

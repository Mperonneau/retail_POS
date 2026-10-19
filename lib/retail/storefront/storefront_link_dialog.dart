import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/payments/open_payment_url.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_close_button.dart';

/// QR code plus copy / share / open for a vitrine or pay link.
Future<void> showStorefrontLinkDialog(
  BuildContext context, {
  required String title,
  required String url,
  String? message,
  String openLabel = 'Ouvrir',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _StorefrontLinkDialog(
      title: title,
      url: url,
      message: message,
      openLabel: openLabel,
    ),
  );
}

class _StorefrontLinkDialog extends StatefulWidget {
  const _StorefrontLinkDialog({
    required this.title,
    required this.url,
    required this.message,
    required this.openLabel,
  });

  final String title;
  final String url;
  final String? message;
  final String openLabel;

  @override
  State<_StorefrontLinkDialog> createState() => _StorefrontLinkDialogState();
}

class _StorefrontLinkDialogState extends State<_StorefrontLinkDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard + 4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacing20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTextStyles.h2(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              if (widget.message != null) ...[
                const SizedBox(height: AppConstants.spacing4),
                Text(widget.message!, style: AppTextStyles.body(color: muted)),
              ],
              const SizedBox(height: AppConstants.spacing16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppConstants.spacing12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                    border: Border.all(color: const Color(0xFFE6E6EE)),
                  ),
                  child: QrImageView(
                    data: widget.url,
                    size: 200,
                    backgroundColor: AppColors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.nearBlack,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.nearBlack,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing12,
                  vertical: AppConstants.spacing10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBackground
                      : AppColors.warmOffWhite,
                  borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                ),
                child: SelectableText(
                  widget.url,
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: _copied ? 'Copié' : 'Copier',
                      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                      variant: AppButtonVariant.secondary,
                      compact: true,
                      onPressed: _copy,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing8),
                  Expanded(
                    child: AppButton(
                      label: 'Partager',
                      icon: Icons.ios_share_rounded,
                      variant: AppButtonVariant.secondary,
                      compact: true,
                      onPressed: () =>
                          Share.share(widget.url, subject: widget.title),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
              AppButton(
                label: widget.openLabel,
                icon: Icons.open_in_new_rounded,
                compact: true,
                onPressed: () => openPaymentUrl(widget.url),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

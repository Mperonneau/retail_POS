import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';

/// Check number, bank, drawer, date, and photo collected at the register.
class CheckPaymentForm extends StatelessWidget {
  final double totalHtg;
  final bool isDark;
  final TextEditingController numberCtrl;
  final TextEditingController bankCtrl;
  final TextEditingController payerCtrl;
  final DateTime date;
  final Uint8List? photo;
  final String? photoError;
  final bool picking;
  final ValueChanged<String> onChanged;
  final ValueChanged<DateTime> onDate;
  final VoidCallback onPickPhoto;

  const CheckPaymentForm({
    super.key,
    required this.totalHtg,
    required this.isDark,
    required this.numberCtrl,
    required this.bankCtrl,
    required this.payerCtrl,
    required this.date,
    required this.photo,
    required this.photoError,
    required this.picking,
    required this.onChanged,
    required this.onDate,
    required this.onPickPhoto,
  });

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) onDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Paiement par chèque', style: AppTextStyles.h3()),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Saisissez les informations du chèque et ajoutez sa photo.',
              style: AppTextStyles.caption(color: muted),
            ),
            const SizedBox(height: AppConstants.spacing12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Montant du chèque', style: AppTextStyles.body()),
                Text(
                  CurrencyFormatter.local(context, totalHtg),
                  style: AppTextStyles.price(),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            AppInput(
              key: const Key('check-number'),
              label: 'Numéro du chèque',
              hint: 'Ex. 104582',
              controller: numberCtrl,
              onChanged: onChanged,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            AppInput(
              key: const Key('check-bank'),
              label: 'Banque',
              hint: 'Ex. Sogebank',
              controller: bankCtrl,
              onChanged: onChanged,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppConstants.spacing12),
            AppInput(
              key: const Key('check-payer'),
              label: 'Nom du tireur',
              hint: 'Nom écrit sur le chèque',
              controller: payerCtrl,
              onChanged: onChanged,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppConstants.spacing12),
            Text(
              'Date du chèque',
              style: AppTextStyles.inputLabel(color: muted),
            ),
            const SizedBox(height: AppConstants.spacing4),
            Material(
              color: isDark ? AppColors.darkBackground : AppColors.white,
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              child: InkWell(
                key: const Key('check-date'),
                onTap: () => _pickDate(context),
                borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusInput,
                    ),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, size: 18, color: muted),
                      const SizedBox(width: 8),
                      Text(
                        DateFormatter.shortDate(date),
                        style: AppTextStyles.body(color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),
            Text(
              'Photo du chèque',
              style: AppTextStyles.inputLabel(color: muted),
            ),
            const SizedBox(height: AppConstants.spacing4),
            Text(
              'Photographiez le recto, lisible. Moins de 1,5 Mo.',
              style: AppTextStyles.caption(color: muted),
            ),
            const SizedBox(height: 8),
            if (photo != null) ...[
              ClipRRect(
                key: const Key('check-photo-preview'),
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: isDark
                      ? AppColors.darkBackground
                      : const Color(0xFFF4F4F4),
                  child: Image.memory(
                    photo!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => SizedBox(
                      height: 140,
                      child: Center(
                        child: Text(
                          'Photo enregistrée',
                          style: AppTextStyles.caption(color: muted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            AppButton(
              key: const Key('check-photo'),
              label: photo == null ? 'Ajouter la photo' : 'Remplacer la photo',
              icon: Icons.add_a_photo_outlined,
              variant: AppButtonVariant.secondary,
              compact: true,
              isLoading: picking,
              onPressed: picking ? null : onPickPhoto,
            ),
            if (photoError != null && photoError!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                photoError!,
                style: AppTextStyles.caption(color: AppColors.boldRed),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

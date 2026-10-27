import 'package:flutter/material.dart';

import '../printing/shop_pdf.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'app_button.dart';
import 'payment_receipt_dialogs.dart';
import 'app_close_button.dart';

/// Post-payment confirmation (matches Restaurant / design: check, amount, receipt actions).
class PaymentSuccessPanel extends StatelessWidget {
  final double amountHtg;
  /// Shown under the header title when [showHeader] is true, e.g. `Pickup · Jean Dupont`.
  final String? contextSubtitle;
  /// Line under the amount, e.g. `Sale #104 paid` or `Table cleared and available`.
  final String statusLine;
  final String? receiptDetailLine;
  final VoidCallback onDone;
  /// When true, shows back / title / subtitle / close row like the POS receipt modal.
  final bool showHeader;
  final String headerTitle;
  final VoidCallback? onHeaderBack;
  final VoidCallback? onHeaderClose;
  /// Optional bottom action (e.g. Restaurant “Back to Tables”). If null, a “Done” text button is used.
  final Widget? doneButton;
  final String? printReceiptName;

  const PaymentSuccessPanel({
    super.key,
    required this.amountHtg,
    this.contextSubtitle,
    required this.statusLine,
    this.receiptDetailLine,
    required this.onDone,
    this.showHeader = false,
    this.headerTitle = 'Paiement',
    this.onHeaderBack,
    this.onHeaderClose,
    this.doneButton,
    this.printReceiptName,
  });

  Widget _body(BuildContext context, Color muted, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.deepGreen,
              size: 56,
            ),
          ),
          const SizedBox(height: AppConstants.spacing24),
          Text(
            'Paiement confirmé !',
            style: AppTextStyles.h1(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacing8),
          Text(
            CurrencyFormatter.local(context, amountHtg),
            style: AppTextStyles.price().copyWith(fontSize: 24),
            textAlign: TextAlign.center,
          ),
          if (receiptDetailLine != null &&
              receiptDetailLine!.trim().isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacing8),
            Text(
              receiptDetailLine!.trim(),
              style: AppTextStyles.body(color: muted),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppConstants.spacing8),
          Text(
            statusLine,
            style: AppTextStyles.body(color: muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacing32),
          AppButton(
            label: 'Envoyer le reçu par WhatsApp',
            onPressed: () => PaymentReceiptDialogs.showWhatsApp(context),
            icon: Icons.send_outlined,
          ),
          const SizedBox(height: AppConstants.spacing12),
          AppButton(
            label: 'Envoyer le reçu par e-mail',
            onPressed: () => PaymentReceiptDialogs.showEmail(context),
            variant: AppButtonVariant.secondary,
            icon: Icons.email_outlined,
          ),
          const SizedBox(height: AppConstants.spacing12),
          AppButton(
            label: 'Imprimer le reçu',
            onPressed: () => PaymentReceiptDialogs.showPrint(
              context,
              receiptName: printReceiptName,
              document: ShopPdf(
                shopName: shopNameFrom(context),
                title: 'REÇU',
                headline: 'Paiement confirmé',
                when: formatPdfStamp(DateTime.now()),
                fields: [
                  if ((printReceiptName ?? '').trim().isNotEmpty)
                    PdfField('Client', printReceiptName!.trim()),
                  PdfField('Statut', statusLine),
                  if ((receiptDetailLine ?? '').trim().isNotEmpty)
                    PdfField('Détail', receiptDetailLine!.trim()),
                ],
                totals: [
                  PdfTotalLine(
                    'Total',
                    localMoney(context, amountHtg),
                    strong: true,
                  ),
                ],
              ),
            ),
            variant: AppButtonVariant.secondary,
            icon: Icons.print_outlined,
          ),
          const SizedBox(height: AppConstants.spacing16),
          if (doneButton != null)
            doneButton!
          else
            Center(
              child: TextButton(
                onPressed: onDone,
                child: Text(
                  'Terminé',
                  style: AppTextStyles.button(
                    color:
                        isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

    if (!showHeader) {
      return Center(child: _body(context, muted, isDark));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                onPressed: onHeaderBack ?? onDone,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      headerTitle,
                      style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.primaryBlue,
                      ),
                    ),
                    if (contextSubtitle != null &&
                        contextSubtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contextSubtitle!.trim(),
                        style: AppTextStyles.caption(color: muted),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              AppCloseButton(onPressed: onHeaderClose ?? onDone),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context, muted, isDark)),
      ],
    );
  }
}

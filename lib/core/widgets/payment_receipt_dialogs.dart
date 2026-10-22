import 'package:flutter/material.dart';

import '../printing/shop_pdf.dart';
import '../utils/input_formatters.dart';
import 'phone_field.dart';

/// Shared receipt actions (Restaurant, Retail, Hotel).
class PaymentReceiptDialogs {
  PaymentReceiptDialogs._();

  static Future<void> showPrint(
    BuildContext context, {
    String? receiptName,
    ShopPdf? document,
    String filename = 'recu.pdf',
  }) {
    final named = receiptName?.trim() ?? '';
    final doc = document ??
        ShopPdf(
          shopName: shopNameFrom(context),
          title: 'REÇU',
          headline: 'Paiement',
          when: formatPdfStamp(DateTime.now()),
          fields: [
            if (named.isNotEmpty) PdfField('Client', named),
          ],
        );
    return printShopPdf(context, filename: filename, document: doc);
  }

  static Future<void> showWhatsApp(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? err;
          return AlertDialog(
            title: const Text('Envoyer par WhatsApp'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => PhoneField(
                controller: ctrl,
                label: 'Numéro de téléphone',
                errorText: err,
                onChanged: (_) => setD2(() => err = null),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) {
                    setD(() => err = 'Veuillez saisir un numéro de téléphone.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reçu envoyé par WhatsApp'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Envoyer'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> showEmail(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? err;
          return AlertDialog(
            title: const Text('Envoyer le reçu par e-mail'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Adresse e-mail',
                  hintText: 'email@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  errorText: err,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                inputFormatters: InputFormatters.email,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () {
                  final email = ctrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    setD(() => err = 'Veuillez saisir une adresse e-mail valide.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reçu envoyé par e-mail'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Envoyer'),
              ),
            ],
          );
        },
      ),
    );
  }
}

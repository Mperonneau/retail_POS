import 'package:flutter/material.dart';

import '../utils/input_formatters.dart';

/// Shared receipt actions (Restaurant, Retail, Hotel) — mock send/print.
class PaymentReceiptDialogs {
  PaymentReceiptDialogs._();

  static Future<void> showPrint(
    BuildContext context, {
    String? receiptName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Imprimer le reçu'),
        content: Text(
          receiptName == null || receiptName.trim().isEmpty
              ? 'Reçu envoyé à l\'imprimante.'
              : 'Reçu pour ${receiptName.trim()} envoyé à l\'imprimante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Numéro de téléphone',
                  hintText: '+509 XXXX-XXXX',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  errorText: err,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: InputFormatters.phone,
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

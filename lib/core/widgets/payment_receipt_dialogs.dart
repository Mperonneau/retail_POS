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
        title: const Text('Print Receipt'),
        content: Text(
          receiptName == null || receiptName.trim().isEmpty
              ? 'Receipt sent to the printer successfully.'
              : 'Receipt for ${receiptName.trim()} sent to the printer successfully.',
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
            title: const Text('Send via WhatsApp'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Phone Number',
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
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) {
                    setD(() => err = 'Please enter a phone number.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Receipt sent via WhatsApp'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Send'),
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
            title: const Text('Send Receipt to Email'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Email Address',
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
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final email = ctrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    setD(() => err = 'Please enter a valid email address.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Receipt sent to email'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Send'),
              ),
            ],
          );
        },
      ),
    );
  }
}

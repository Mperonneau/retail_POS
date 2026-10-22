import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Font? _regular;
pw.Font? _bold;

Future<pw.ThemeData> _receiptTheme() async {
  _regular ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf'),
  );
  _bold ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf'),
  );
  return pw.ThemeData.withFont(base: _regular, bold: _bold);
}

/// One-page receipt. The text is the same receipt sent by WhatsApp and e-mail.
Future<Uint8List> buildSaleReceiptPdf({
  required String title,
  required String text,
}) async {
  final theme = await _receiptTheme();
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              text,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

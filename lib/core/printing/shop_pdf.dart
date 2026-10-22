import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/currency_settings.dart';
import '../models/order_history.dart';
import '../providers/auth_provider.dart';
import '../providers/currency_settings_provider.dart';
import '../utils/currency_formatter.dart';
import 'pdf_theme.dart';

class PdfField {
  const PdfField(this.label, this.value);

  final String label;
  final String value;
}

class PdfDocLine {
  const PdfDocLine({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.total,
  });

  final String name;
  final String quantity;
  final String unit;
  final String total;
}

class PdfTotalLine {
  const PdfTotalLine(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;
}

class ShopPdf {
  const ShopPdf({
    required this.shopName,
    required this.title,
    required this.headline,
    this.number = '',
    required this.when,
    this.fields = const [],
    this.lines = const [],
    this.totals = const [],
    this.notes = const [],
  });

  final String shopName;
  final String title;
  final String headline;
  final String number;
  final String when;
  final List<PdfField> fields;
  final List<PdfDocLine> lines;
  final List<PdfTotalLine> totals;
  final List<String> notes;
}

String formatPdfStamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
}

String shopNameFrom(BuildContext context) {
  try {
    final name = ProviderScope.containerOf(context)
        .read(authProvider)
        .businessName
        ?.trim();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {}
  return 'Boutique';
}

String localMoney(BuildContext context, double amount) {
  try {
    final settings =
        ProviderScope.containerOf(context).read(currencySettingsProvider);
    return CurrencyFormatter.formatLocalFromSettings(settings, amount);
  } catch (_) {
    return CurrencyFormatter.formatLocalFromSettings(
      CurrencySettings.haitiDefault,
      amount,
    );
  }
}

bool _narrow(PdfPageFormat format) => format.width <= 120 * PdfPageFormat.mm;

bool _roll(PdfPageFormat format) =>
    !format.height.isFinite || format.height > 600 * PdfPageFormat.mm;

double _margin(PdfPageFormat format) {
  final preferred = _narrow(format) ? 3.5 * PdfPageFormat.mm : 16 * PdfPageFormat.mm;
  final limit = format.width * 0.12;
  return math.min(preferred, math.max(2 * PdfPageFormat.mm, limit));
}

Future<Uint8List> buildShopPdf({
  required PdfPageFormat format,
  required ShopPdf document,
}) async {
  final theme = await shopPdfTheme();
  final width = format.width.isFinite && format.width > 40 * PdfPageFormat.mm
      ? format.width
      : PdfPageFormat.a4.width;
  final paper = PdfPageFormat(width, format.height);
  final narrow = _narrow(paper);
  final margin = _margin(paper);
  final parts = _parts(document, narrow);
  final doc = pw.Document();

  if (_roll(paper)) {
    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(width, double.infinity),
          margin: pw.EdgeInsets.all(margin),
          theme: theme,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: parts,
        ),
      ),
    );
  } else {
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            width,
            format.height.isFinite ? format.height : PdfPageFormat.a4.height,
          ),
          margin: pw.EdgeInsets.all(margin),
          theme: theme,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => parts,
      ),
    );
  }
  return doc.save();
}

Future<void> printShopPdf(
  BuildContext context, {
  required String filename,
  required ShopPdf document,
}) async {
  try {
    await Printing.layoutPdf(
      name: filename,
      onLayout: (format) => buildShopPdf(format: format, document: document),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Le document n\'a pas pu être préparé.'),
      ),
    );
  }
}

ShopPdf shopPdfFromHistory({
  required OrderHistoryRecord record,
  required String shopName,
  required String Function(double amount) money,
}) {
  final lines = record.paymentLines;
  final notes = <String>[
    if (lines != null && lines.isNotEmpty)
      for (final line in lines) '${line.method.label} · ${money(line.amountHtg)}',
  ];
  return ShopPdf(
    shopName: shopName,
    title: 'REÇU',
    headline: 'Paiement confirmé',
    number: record.receiptNumber,
    when: formatPdfStamp(record.paidAt),
    fields: [
      PdfField('Origine', record.source),
      if ((record.receiptName ?? '').trim().isNotEmpty)
        PdfField('Client', record.receiptName!.trim()),
      if (lines == null || lines.isEmpty)
        PdfField('Paiement', record.paymentMethod.label),
      if ((record.paymentLastFour ?? '').trim().isNotEmpty)
        PdfField('Référence', '•••• ${record.paymentLastFour!.trim()}'),
    ],
    lines: [
      for (final item in record.items)
        PdfDocLine(
          name: item.name,
          quantity: '${item.quantity}',
          unit: money(item.priceHtg),
          total: money(item.lineTotalHtg),
        ),
    ],
    totals: [
      PdfTotalLine('Sous-total', money(record.subtotal)),
      if (record.discountPercent > 0)
        PdfTotalLine(
          'Remise (${record.discountPercent.toStringAsFixed(0)} %)',
          money(-record.discountAmount),
        ),
      if (record.taxPercent > 0)
        PdfTotalLine(
          'Taxe (${record.taxPercent.toStringAsFixed(0)} %)',
          money(record.taxAmount),
        ),
      if (record.serviceChargePercent > 0)
        PdfTotalLine(
          'Service (${record.serviceChargePercent.toStringAsFixed(0)} %)',
          money(record.serviceChargeAmount),
        ),
      PdfTotalLine('Total', money(record.total), strong: true),
    ],
    notes: notes,
  );
}

List<pw.Widget> _parts(ShopPdf document, bool narrow) {
  final body = narrow ? 9.0 : 11.0;
  final small = narrow ? 8.0 : 9.0;
  return [
    pw.Text(
      document.shopName,
      style: pw.TextStyle(fontSize: narrow ? 12 : 16, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: narrow ? 6 : 10),
    pw.Text(
      document.title,
      style: pw.TextStyle(
        fontSize: narrow ? 14 : 20,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1.4,
      ),
    ),
    pw.SizedBox(height: 3),
    pw.Text(document.headline, style: pw.TextStyle(fontSize: body)),
    pw.SizedBox(height: narrow ? 6 : 10),
    pw.Container(height: 1, color: PdfColors.grey600),
    pw.SizedBox(height: narrow ? 6 : 10),
    if (document.number.trim().isNotEmpty)
      _field('N°', document.number, body),
    _field('Date', document.when, body),
    for (final field in document.fields)
      if (field.value.trim().isNotEmpty) _field(field.label, field.value, body),
    if (document.lines.isNotEmpty) ...[
      pw.SizedBox(height: narrow ? 8 : 14),
      if (narrow) ..._narrowLines(document.lines, body, small) else _table(document.lines, body, small),
    ],
    if (document.totals.isNotEmpty) ...[
      pw.SizedBox(height: narrow ? 8 : 12),
      _totals(document.totals, body, narrow),
    ],
    if (document.notes.isNotEmpty) ...[
      pw.SizedBox(height: narrow ? 8 : 12),
      for (final note in document.notes)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text(note, style: pw.TextStyle(fontSize: small, color: PdfColors.grey700)),
        ),
    ],
    pw.SizedBox(height: narrow ? 12 : 22),
    pw.Text('Merci de votre confiance.', style: pw.TextStyle(fontSize: body)),
  ];
}

pw.Widget _field(String label, String value, double size) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: size),
        children: [
          pw.TextSpan(
            text: '$label : ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: value),
        ],
      ),
    ),
  );
}

pw.Widget _table(List<PdfDocLine> lines, double body, double small) {
  final header = pw.TextStyle(fontSize: small, color: PdfColors.grey700);
  final cell = pw.TextStyle(fontSize: body);
  pw.Widget text(String value, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: pw.Text(value, style: style, textAlign: align),
    );
  }

  pw.TableRow row(List<String> values, pw.TextStyle style, {bool headerRow = false}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: headerRow ? PdfColors.grey600 : PdfColors.grey300),
        ),
      ),
      children: [
        text(values[0], style),
        text(values[1], style, align: pw.TextAlign.center),
        text(values[2], style, align: pw.TextAlign.right),
        text(values[3], style, align: pw.TextAlign.right),
      ],
    );
  }

  return pw.Table(
    columnWidths: {
      0: const pw.FlexColumnWidth(5.2),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(2.1),
      3: const pw.FlexColumnWidth(2.1),
    },
    children: [
      row(['Désignation', 'Qté', 'Prix', 'Total'], header, headerRow: true),
      for (final line in lines)
        row([line.name, line.quantity, line.unit, line.total], cell),
    ],
  );
}

List<pw.Widget> _narrowLines(List<PdfDocLine> lines, double body, double small) {
  final header = pw.TextStyle(fontSize: small, color: PdfColors.grey700);
  final cell = pw.TextStyle(fontSize: body);
  return [
    pw.Row(
      children: [
        pw.Expanded(child: pw.Text('Désignation', style: header)),
        pw.Text('Total', style: header),
      ],
    ),
    pw.Container(height: 1, color: PdfColors.grey600),
    for (final line in lines) ...[
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(line.name, style: cell)),
          pw.SizedBox(width: 6),
          pw.Text(line.total, style: cell),
        ],
      ),
      pw.Text(
        '${line.quantity} × ${line.unit}',
        style: pw.TextStyle(fontSize: small, color: PdfColors.grey700),
      ),
    ],
  ];
}

pw.Widget _totals(List<PdfTotalLine> totals, double body, bool narrow) {
  return pw.Column(
    crossAxisAlignment:
        narrow ? pw.CrossAxisAlignment.stretch : pw.CrossAxisAlignment.end,
    children: [
      for (final line in totals)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            mainAxisSize: narrow ? pw.MainAxisSize.max : pw.MainAxisSize.min,
            children: [
              pw.Text(
                line.label,
                style: pw.TextStyle(
                  fontSize: line.strong ? body + 1 : body,
                  fontWeight: line.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(width: 16),
              if (!narrow) pw.Text(
                line.value,
                style: pw.TextStyle(
                  fontSize: line.strong ? body + 1 : body,
                  fontWeight: line.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              if (narrow) pw.Expanded(
                child: pw.Text(
                  line.value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: line.strong ? body + 1 : body,
                    fontWeight: line.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

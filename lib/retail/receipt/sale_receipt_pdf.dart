import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/order_history.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import 'sale_receipt_text.dart';

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

/// Thermal rolls and other narrow stock. Wider paper keeps the full table.
bool receiptPdfIsNarrow(PdfPageFormat format) =>
    format.width <= 120 * PdfPageFormat.mm;

/// A roll reports an unbounded height. Size that page to the receipt.
bool receiptPdfIsRoll(PdfPageFormat format) =>
    !format.height.isFinite || format.height > 600 * PdfPageFormat.mm;

double _margin(PdfPageFormat format) {
  final preferred = receiptPdfIsNarrow(format)
      ? 3.5 * PdfPageFormat.mm
      : 16 * PdfPageFormat.mm;
  final limit = format.width * 0.12;
  return math.min(preferred, math.max(2 * PdfPageFormat.mm, limit));
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime dt) =>
    '${_two(dt.day)}/${_two(dt.month)}/${dt.year}  ${_two(dt.hour)}:${_two(dt.minute)}';

String _day(DateTime dt) => '${_two(dt.day)}/${_two(dt.month)}/${dt.year}';

String _percent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// Printable receipt laid out like a devis.
///
/// [format] is the paper the printer asked for. A roll grows to the
/// receipt; a sheet paginates. Narrow paper drops the unit-price column.
Future<Uint8List> buildSaleReceiptPdf({
  required PdfPageFormat format,
  required RetailOrder order,
  required SaleReceiptFigures figures,
  required String shopName,
  required String Function(double amount) money,
  String? usdTotal,
}) async {
  final theme = await _receiptTheme();
  final width = format.width.isFinite && format.width > 40 * PdfPageFormat.mm
      ? format.width
      : PdfPageFormat.a4.width;
  final paper = PdfPageFormat(width, format.height);
  final narrow = receiptPdfIsNarrow(paper);
  final margin = _margin(paper);
  final doc = pw.Document();

  final parts = _parts(
    order: order,
    figures: figures,
    shopName: shopName,
    money: money,
    usdTotal: usdTotal,
    narrow: narrow,
  );

  if (receiptPdfIsRoll(paper)) {
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
    final page = PdfPageFormat(
      width,
      format.height.isFinite ? format.height : PdfPageFormat.a4.height,
    );
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: page,
          margin: pw.EdgeInsets.all(margin),
          theme: theme,
        ),
        maxPages: 20,
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ),
        build: (context) => parts,
      ),
    );
  }

  return doc.save();
}

List<pw.Widget> _parts({
  required RetailOrder order,
  required SaleReceiptFigures figures,
  required String shopName,
  required String Function(double amount) money,
  required String? usdTotal,
  required bool narrow,
}) {
  final body = narrow ? 8.0 : 11.0;
  final small = narrow ? 7.0 : 9.0;
  return [
    ..._header(order, shopName, narrow, body),
    pw.SizedBox(height: narrow ? 8 : 16),
    ..._itemRows(order, money, narrow, body, small),
    pw.SizedBox(height: narrow ? 8 : 14),
    _totals(figures, money, usdTotal, narrow, body),
    pw.SizedBox(height: narrow ? 8 : 16),
    ..._payment(order, body, small),
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

List<pw.Widget> _header(
  RetailOrder order,
  String shopName,
  bool narrow,
  double body,
) {
  final shop = shopName.trim();
  final fields = <pw.Widget>[
    _field('Numéro', order.orderNumber, body),
    _field('Date', _stamp(order.createdAt), body),
  ];
  final client = order.clientName?.trim() ?? '';
  if (client.isNotEmpty) fields.add(_field('Client', client, body));
  final phone = order.clientPhone?.trim() ?? '';
  if (phone.isNotEmpty) fields.add(_field('Téléphone', phone, body));
  final email = order.clientEmail?.trim() ?? '';
  if (email.isNotEmpty) fields.add(_field('E-mail', email, body));
  fields.add(_field('Mode', order.fulfillmentMode.label, body));
  if (order.fulfillmentMode == RetailFulfillmentMode.delivery) {
    final place = order.deliveryLocation?.trim() ?? '';
    if (place.isNotEmpty) fields.add(_field('Adresse', place, body));
    final deliveryPhone = order.deliveryPhone?.trim() ?? '';
    if (deliveryPhone.isNotEmpty) {
      fields.add(_field('Tél. livraison', deliveryPhone, body));
    }
  }

  return [
    if (shop.isNotEmpty)
      pw.Text(
        shop,
        style: pw.TextStyle(
          fontSize: narrow ? 13 : 20,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    pw.SizedBox(height: narrow ? 8 : 14),
    pw.Text(
      'REÇU',
      style: pw.TextStyle(
        fontSize: narrow ? 12 : 16,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
    pw.SizedBox(height: 3),
    pw.Text(saleReceiptHeadline(order), style: pw.TextStyle(fontSize: body)),
    pw.SizedBox(height: narrow ? 6 : 10),
    ...fields,
  ];
}

List<pw.Widget> _itemRows(
  RetailOrder order,
  String Function(double amount) money,
  bool narrow,
  double body,
  double small,
) {
  final headerStyle = pw.TextStyle(fontSize: small, color: PdfColors.grey700);
  final cellStyle = pw.TextStyle(fontSize: body);

  if (narrow) {
    return _narrowItems(order, money, small, headerStyle, cellStyle);
  }

  const widths = {
    0: pw.FlexColumnWidth(5.2),
    1: pw.FlexColumnWidth(1),
    2: pw.FlexColumnWidth(2.1),
    3: pw.FlexColumnWidth(2.1),
  };

  pw.Widget cell(
    String text, {
    bool right = false,
    bool center = false,
    pw.TextStyle? style,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: pw.Text(
        text,
        textAlign: right
            ? pw.TextAlign.right
            : center
            ? pw.TextAlign.center
            : pw.TextAlign.left,
        style: style ?? cellStyle,
      ),
    );
  }

  // One row per widget so a long receipt continues on the next sheet.
  pw.Widget band(List<pw.Widget> cells, {bool header = false}) {
    return pw.Table(
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: header ? PdfColors.grey600 : PdfColors.grey300,
                width: header ? 0.7 : 0.4,
              ),
            ),
          ),
          children: cells,
        ),
      ],
    );
  }

  return [
    band([
      cell('Désignation', style: headerStyle),
      cell('Qté', center: true, style: headerStyle),
      cell('Prix unitaire', right: true, style: headerStyle),
      cell('Total', right: true, style: headerStyle),
    ], header: true),
    for (final line in order.lines)
      band([
        cell(line.productName),
        cell('${line.quantity}', center: true),
        cell(money(line.unitPriceHtg), right: true),
        cell(money(line.lineTotalHtg), right: true),
      ]),
  ];
}

/// One article per block so the amount stays on one line on a narrow roll.
List<pw.Widget> _narrowItems(
  RetailOrder order,
  String Function(double amount) money,
  double small,
  pw.TextStyle headerStyle,
  pw.TextStyle cellStyle,
) {
  pw.Widget rule({bool strong = false}) => pw.Container(
    height: strong ? 0.7 : 0.4,
    color: strong ? PdfColors.grey600 : PdfColors.grey300,
  );

  return [
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text('Désignation', style: headerStyle)),
          pw.Text('Total', style: headerStyle),
        ],
      ),
    ),
    rule(strong: true),
    for (final line in order.lines) ...[
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(line.productName, style: cellStyle)),
          pw.SizedBox(width: 6),
          pw.Text(money(line.lineTotalHtg), style: cellStyle),
        ],
      ),
      pw.Text(
        '${line.quantity} × ${money(line.unitPriceHtg)}',
        style: pw.TextStyle(fontSize: small, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 3),
      rule(),
    ],
  ];
}

pw.Widget _totals(
  SaleReceiptFigures figures,
  String Function(double amount) money,
  String? usdTotal,
  bool narrow,
  double body,
) {
  final rows = <(String, String, bool)>[
    ('Sous-total', money(figures.subtotal), false),
    if (figures.discountAmount > 0)
      (
        'Remise (${_percent(figures.discountPercent)} %)',
        '-${money(figures.discountAmount)}',
        false,
      ),
    if (figures.taxAmount > 0)
      (
        'Taxe (${_percent(figures.taxPercent)} %)',
        money(figures.taxAmount),
        false,
      ),
    if (figures.serviceAmount > 0)
      (
        'Frais de service (${_percent(figures.servicePercent)} %)',
        money(figures.serviceAmount),
        false,
      ),
    if (figures.deliveryFee > 0)
      ('Frais de livraison', money(figures.deliveryFee), false),
    ('Total', money(figures.total), true),
  ];

  pw.Widget line(String label, String value, {required bool bold}) {
    final style = pw.TextStyle(
      fontSize: bold ? (narrow ? body + 1 : body + 2) : body,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    if (narrow) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.SizedBox(width: 6),
            pw.Text(value, style: style),
          ],
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        '$label : $value',
        textAlign: pw.TextAlign.right,
        style: style,
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: narrow
        ? pw.CrossAxisAlignment.stretch
        : pw.CrossAxisAlignment.end,
    children: [
      for (final row in rows) line(row.$1, row.$2, bold: row.$3),
      if (usdTotal != null && usdTotal.trim().isNotEmpty)
        pw.Text(
          usdTotal.trim(),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(fontSize: body - 1, color: PdfColors.grey700),
        ),
    ],
  );
}

List<pw.Widget> _payment(RetailOrder order, double body, double small) {
  final check = order.checkPayment;
  return [
    _field('Paiement', order.paymentMethod.label, body),
    if (check != null) ...[
      _field('N° chèque', check.number, small),
      _field('Banque', check.bank, small),
      _field('Tireur', check.payerName, small),
      _field('Date du chèque', _day(check.date), small),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(
          check.clearanceLabel,
          style: pw.TextStyle(fontSize: small),
        ),
      ),
      if (check.imageBytes != null)
        pw.Text(
          'Photo du chèque enregistrée.',
          style: pw.TextStyle(fontSize: small, color: PdfColors.grey700),
        ),
    ],
  ];
}

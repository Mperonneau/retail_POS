import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/models/retail_check_payment.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/retail/receipt/sale_receipt_pdf.dart';
import 'package:retail_pos/retail/receipt/sale_receipt_text.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Intl.defaultLocale = 'fr';
    await initializeDateFormatting('fr');
  });

  RetailOrder sample({bool cleared = false, String? clearedBy}) {
    return RetailOrder(
      id: 'pos-1',
      orderNumber: 'ORD-2026-4596',
      clientName: 'Marie Joseph',
      clientPhone: '3700-1234',
      status: cleared ? RetailOrderStatus.paid : RetailOrderStatus.checkPending,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.check,
      checkPayment: RetailCheckPayment(
        number: '104582',
        bank: 'Sogebank',
        payerName: 'Marie Joseph',
        date: DateTime(2026, 10, 22),
        imageDataUrl: 'data:image/png;base64,aGk=',
        cleared: cleared,
        clearedBy: cleared ? clearedBy : null,
      ),
      lines: const [
        RetailOrderLine(
          productName: 'Riz',
          productId: 1,
          quantity: 2,
          unitPriceHtg: 250,
        ),
      ],
      createdAt: DateTime(2026, 10, 22, 8, 23),
      paidAt: DateTime(2026, 10, 22, 8, 23),
    );
  }

  const figures = SaleReceiptFigures(
    subtotal: 500,
    discountPercent: 0,
    discountAmount: 0,
    taxPercent: 0,
    taxAmount: 0,
    servicePercent: 0,
    serviceAmount: 0,
    deliveryFee: 0,
    total: 500,
  );

  String money(double amount) => '${amount.toStringAsFixed(2)} HTG';

  test('a pending check is a receipt, not a confirmed payment', () {
    final text = saleReceiptText(
      order: sample(),
      figures: figures,
      shopName: 'Boutique Soleil',
      money: money,
    );

    expect(saleReceiptHeadline(sample()), 'Chèque en attente');
    expect(text, isNot(contains('Paiement confirmé')));
    expect(text, contains('Boutique Soleil'));
    expect(text, contains('Reçu ORD-2026-4596'));
    expect(text, contains('Client : Marie Joseph'));
    expect(text, contains('2 × Riz'));
    expect(text, contains('TOTAL : 500.00 HTG'));
    expect(text, contains('N° chèque : 104582'));
    expect(text, contains('Banque : Sogebank'));
    expect(text, contains('En attente de compensation'));
    expect(text, contains('Photo du chèque enregistrée.'));
  });

  test('a cleared check is a confirmed payment', () {
    final order = sample(cleared: true, clearedBy: 'Nadia Pierre');
    expect(saleReceiptHeadline(order), 'Paiement confirmé !');
    final text = saleReceiptText(
      order: order,
      figures: figures,
      shopName: 'Boutique Soleil',
      money: money,
    );
    expect(text, contains('Chèque compensé par : Nadia Pierre'));
  });

  test('WhatsApp and e-mail links carry the receipt', () {
    const body = 'Reçu ORD-2026-4596';
    expect(
      whatsAppReceiptUrl(phone: '3700-1234', text: body),
      'https://wa.me/50937001234?text=Re%C3%A7u%20ORD-2026-4596',
    );
    expect(
      whatsAppReceiptUrl(text: body),
      'https://wa.me/?text=Re%C3%A7u%20ORD-2026-4596',
    );
    final mail = emailReceiptUrl(
      to: 'marie@example.com',
      subject: 'Reçu ORD-2026-4596',
      body: body,
    );
    expect(mail, startsWith('mailto:marie@example.com'));
    expect(mail, contains('subject='));
    expect(mail, contains('body='));
  });

  test('the receipt PDF fits a page and a thermal roll', () async {
    Future<Uint8List> build(PdfPageFormat format) {
      return buildSaleReceiptPdf(
        format: format,
        order: sample(cleared: true, clearedBy: 'Nadia Pierre'),
        figures: figures,
        shopName: 'Boutique Soleil',
        money: money,
      );
    }

    final page = await build(PdfPageFormat.a4);
    final letter = await build(PdfPageFormat.letter);
    final roll = await build(PdfPageFormat.roll80);
    expect(String.fromCharCodes(page.take(5)), '%PDF-');
    expect(String.fromCharCodes(letter.take(5)), '%PDF-');
    expect(String.fromCharCodes(roll.take(5)), '%PDF-');
    expect(receiptPdfIsNarrow(PdfPageFormat.roll80), isTrue);
    expect(receiptPdfIsNarrow(PdfPageFormat.roll57), isTrue);
    expect(receiptPdfIsNarrow(PdfPageFormat.a4), isFalse);
    expect(receiptPdfIsNarrow(PdfPageFormat.letter), isFalse);
    expect(receiptPdfIsRoll(PdfPageFormat.roll80), isTrue);
    expect(receiptPdfIsRoll(PdfPageFormat.a4), isFalse);
    // A roll is cut to the receipt, not a fixed sheet of blank paper.
    final rollBox = _mediaBox(roll);
    expect(rollBox, isNotNull);
    expect(rollBox!.$1, closeTo(80 * PdfPageFormat.mm, 1));
    expect(rollBox.$2, greaterThan(40 * PdfPageFormat.mm));
    expect(rollBox.$2, lessThan(180 * PdfPageFormat.mm));
    final a4Box = _mediaBox(page);
    expect(a4Box, isNotNull);
    expect(a4Box!.$1, closeTo(PdfPageFormat.a4.width, 1));
    expect(a4Box.$2, closeTo(PdfPageFormat.a4.height, 1));
    expect(saleReceiptFilename(sample()), 'recu-ORD-2026-4596.pdf');
  });

  test('a long receipt continues on the next sheet', () async {
    final order = RetailOrder(
      id: 'pos-long',
      orderNumber: 'ORD-2026-9000',
      status: RetailOrderStatus.paid,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.cash,
      lines: [
        for (var i = 0; i < 48; i++)
          RetailOrderLine(
            productName: 'Article ${i + 1}',
            productId: i,
            quantity: 1,
            unitPriceHtg: 25,
          ),
      ],
      createdAt: DateTime(2026, 10, 22, 9),
      paidAt: DateTime(2026, 10, 22, 9),
    );
    final bytes = await buildSaleReceiptPdf(
      format: PdfPageFormat.a4,
      order: order,
      figures: figures,
      shopName: 'Boutique Soleil',
      money: money,
    );
    expect(_mediaBoxCount(bytes), greaterThan(1));
  });
}

/// First page size in points, read from the PDF page dictionary.
(double, double)? _mediaBox(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  final match = RegExp(
    r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]',
  ).firstMatch(text);
  if (match == null) return null;
  final width = double.parse(match.group(3)!) - double.parse(match.group(1)!);
  final height = double.parse(match.group(4)!) - double.parse(match.group(2)!);
  return (width, height);
}

int _mediaBoxCount(Uint8List bytes) {
  return RegExp(r'/MediaBox').allMatches(String.fromCharCodes(bytes)).length;
}

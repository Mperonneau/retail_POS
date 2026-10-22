import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/printing/shop_pdf.dart';
import 'package:retail_pos/retail/cash/cash_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a receipt, a narrow receipt, and a cash report are PDFs', () async {
    final record = OrderHistoryRecord(
      receiptNumber: 'RCP-2026-008',
      paidAt: DateTime(2026, 10, 22, 14, 44),
      receiptName: 'Café Étoile',
      source: 'Table 4',
      items: const [
        OrderHistoryItem(name: 'Riz blanc', quantity: 2, priceHtg: 150),
      ],
      paymentMethod: PaymentMethodType.cash,
      module: OrderHistoryModule.restaurant,
      taxPercent: 10,
    );
    final document = shopPdfFromHistory(
      record: record,
      shopName: 'Boutique Soleil',
      money: (amount) => '${amount.toStringAsFixed(2)} HTG',
    );

    final a4 = await buildShopPdf(format: PdfPageFormat.a4, document: document);
    final roll = await buildShopPdf(
      format: PdfPageFormat.roll80,
      document: document,
    );
    final cash = await buildSessionReportPdf(
      CashReportFigures(
        shopName: 'Boutique Soleil',
        openedBy: 'Nadia Pierre',
        openedAt: DateTime(2026, 10, 22, 8),
        openingHtg: 1000,
        openingUsd: 50,
        inHtg: 200,
        inUsd: 0,
        outHtg: 0,
        outUsd: 0,
        expectedHtg: 1200,
        expectedUsd: 50,
        cardUsd: 10,
        moncashHtg: 0,
        checkHtg: 0,
        movements: const [],
      ),
    );

    expect(String.fromCharCodes(a4.take(5)), '%PDF-');
    expect(String.fromCharCodes(roll.take(5)), '%PDF-');
    expect(String.fromCharCodes(cash.take(5)), '%PDF-');
    expect(a4.length, greaterThan(1000));
    expect(cash.length, greaterThan(1000));
  });
}

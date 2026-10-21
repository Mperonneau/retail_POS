import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/models/customer.dart';
import 'package:retail_pos/core/models/paylink.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/screens/paylinks/new_paylink_modal.dart';
import 'package:retail_pos/core/screens/paylinks/payment_documents.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  final order = RetailOrder(
    id: 'ord_45',
    orderNumber: 'ORD-2026-0045',
    clientName: 'Moliere',
    status: RetailOrderStatus.paid,
    paymentSource: RetailPaymentSource.pos,
    lines: const [
      RetailOrderLine(
        productName: 'Riz',
        productId: 1,
        quantity: 1,
        unitPriceHtg: 500,
      ),
    ],
    createdAt: DateTime(2026, 10, 21),
    paidAt: DateTime(2026, 10, 21),
  );
  final quote = MockRetailQuote(
    id: 'qte_2',
    quoteNumber: 'QTE-2026-0002',
    checkoutId: 'chk',
    clientName: 'Jean',
    lines: const [],
    createdAt: DateTime(2026, 10, 21),
  );
  final cancelled = quote.copyWith(
    id: 'qte_x',
    quoteNumber: 'QTE-2026-0099',
    status: MockRetailQuoteStatus.cancelled,
  );

  test('an empty search does not offer a document', () {
    expect(
      searchPaymentDocuments(query: '   ', orders: [order], quotes: [quote]),
      isEmpty,
    );
  });

  test(
    'a number finds the commande or the devis and skips a cancelled devis',
    () {
      final orders = searchPaymentDocuments(
        query: '0045',
        orders: [order],
        quotes: [quote, cancelled],
      );
      expect(orders, hasLength(1));
      expect(orders.single.number, 'ORD-2026-0045');
      expect(orders.single.kindLabel, 'Commande');

      final quotes = searchPaymentDocuments(
        query: 'qte-2026-0002',
        orders: [order],
        quotes: [quote, cancelled],
      );
      expect(quotes.single.kindLabel, 'Devis');
      expect(quotes.single.number, 'QTE-2026-0002');

      expect(
        searchPaymentDocuments(
          query: '0099',
          orders: [order],
          quotes: [quote, cancelled],
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'the create button stays off until a commande or devis is chosen',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: _Open())),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Créer le lien'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Créer le lien'),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField).first, '0045');
      await tester.pump();
      await tester.tap(find.textContaining('ORD-2026-0045'));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Créer le lien'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}

class _Open extends ConsumerWidget {
  const _Open();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () => showNewPayLinkModal(
          context,
          isDark: false,
          payLinkProvider: retailPayLinkProvider,
          customerProvider: customerProvider,
        ),
        child: const Text('open'),
      ),
    );
  }
}

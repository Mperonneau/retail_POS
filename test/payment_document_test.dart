import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/models/customer.dart';
import 'package:retail_pos/core/models/paylink.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/screens/paylinks/new_paylink_modal.dart';
import 'package:retail_pos/core/screens/paylinks/payment_documents.dart';
import 'package:retail_pos/core/widgets/payment_link_dialog.dart';
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
      expect(find.text('Rechercher un numéro *'), findsNothing);
      expect(find.text('Boutique Madame Pierre'), findsWidgets);
      expect(find.textContaining('ORD-2026-0045'), findsOneWidget);

      await tester.tap(find.byTooltip('Retirer'));
      await tester.pump();

      expect(find.text('Rechercher un numéro *'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Créer le lien'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  test('a shared link names the commande, the client, and the url', () {
    final message = paymentLinkShareMessage(
      url: 'https://checkout.stripe.com/c/pay/cs_test_abc',
      number: 'QTE-2026-0001',
      kindLabel: 'Commande',
      clientName: 'Restaurant Ti Kay',
      amountLabel: '12 292,00 HTG',
      phone: '+509 41235678',
    );
    expect(message, contains('Commande : QTE-2026-0001'));
    expect(message, contains('Client : Restaurant Ti Kay'));
    expect(message, contains('Montant : 12 292,00 HTG'));
    expect(message, contains('Téléphone : +509 41235678'));
    expect(message, contains('https://checkout.stripe.com/c/pay/cs_test_abc'));
    expect(
      paymentLinkShareMessage(
        url: 'https://checkout.stripe.com/c/pay/cs_test_abc',
        number: 'ORD-2026-0045',
        clientName: 'Moliere',
        phone: 'ORD-2026-0045',
      ),
      isNot(contains('Téléphone')),
    );
  });

  testWidgets('the copy screen does not show the full link', (tester) async {
    const url = 'https://checkout.stripe.com/c/pay/cs_test_hidden';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPaymentLinkSuccessDialog(
              context,
              isDark: false,
              headline: 'Lien créé',
              title: 'Le lien QTE-2026-0001 est prêt.',
              pathOrUrl: url,
              shareText: paymentLinkShareMessage(
                url: url,
                number: 'QTE-2026-0001',
                kindLabel: 'Commande',
                clientName: 'Restaurant Ti Kay',
                amountLabel: '12 292,00 HTG',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments;
          if (args is Map) copied = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('checkout.stripe.com'), findsNothing);
    expect(find.text('Copier le lien'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);

    await tester.tap(find.text('Copier le lien'));
    await tester.pump();
    expect(find.text('Lien copié'), findsOneWidget);
    expect(copied, url);
    await tester.pump(const Duration(seconds: 2));
  });
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

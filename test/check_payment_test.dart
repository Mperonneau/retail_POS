import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/mock/mock_retail_orders.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/models/retail_check_payment.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/screens/order_history/order_history_screen.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/retail/models/retail_cart_entry.dart';
import 'package:retail_pos/retail/screens/checkout_wizard.dart';
import 'package:retail_pos/retail/widgets/check_photo_limits.dart';
import 'package:retail_pos/retail/widgets/check_photo_pick.dart';
import 'package:retail_pos/retail/widgets/product_photo_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1×1 transparent PNG.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    Intl.defaultLocale = 'fr';
    await initializeDateFormatting('fr');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalStore.instance.debugReset();
    checkPhotoPicker = pickCheckPhoto;
  });

  test('check details survive on the order and skip the service fee', () {
    final order = RetailOrder(
      id: 'pos-1',
      orderNumber: 'ORD-2026-1',
      status: RetailOrderStatus.paid,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.check,
      checkPayment: RetailCheckPayment(
        number: '104582',
        bank: 'Sogebank',
        payerName: 'Marie Joseph',
        date: DateTime(2026, 10, 22, 15, 4),
        imageDataUrl: RetailCheckPayment.dataUrlFor(_tinyPng, 'image/png'),
      ),
      lines: const [
        RetailOrderLine(
          productName: 'Riz',
          productId: 1,
          quantity: 1,
          unitPriceHtg: 100,
        ),
      ],
      serviceChargePercent: 10,
      createdAt: DateTime(2026, 10, 22),
      paidAt: DateTime(2026, 10, 22),
    );

    final restored = RetailOrder.fromJson(order.toJson())!;
    expect(restored.paymentMethod, PaymentMethodType.check);
    expect(restored.checkPayment!.number, '104582');
    expect(restored.checkPayment!.bank, 'Sogebank');
    expect(restored.checkPayment!.payerName, 'Marie Joseph');
    expect(restored.checkPayment!.date, DateTime(2026, 10, 22));
    expect(restored.checkPayment!.imageBytes, _tinyPng);
    expect(restored.checkPayment!.cleared, isFalse);
    expect(restored.appliesElectronicServiceFee, isFalse);
    expect(restored.serviceChargeAmountHtg, 0);

    final legacy = order.toJson();
    (legacy['checkPayment'] as Map).remove('cleared');
    (legacy['checkPayment'] as Map).remove('clearedAt');
    expect(RetailOrder.fromJson(legacy)!.checkPayment!.cleared, isTrue);

    final json = order.toJson();
    json['paymentMethod'] = 'wire';
    expect(RetailOrder.fromJson(json)!.paymentMethod, PaymentMethodType.cash);
    expect(
      RetailCheckPayment.compose(
        number: ' ',
        bank: 'Sogebank',
        payerName: 'Marie',
        date: DateTime(2026, 10, 22),
        photo: _tinyPng,
        mime: 'image/png',
      ),
      isNull,
    );
  });

  testWidgets('Chèque stays blocked until the details and the photo exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final product = container.read(mockProductsProvider).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: RetailCheckoutWizard(
              cart: [RetailCartEntry(product: product)],
              discountPercent: 0,
              initialStepIndex: 2,
              onSuccess: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Paiement'), findsWidgets);
    await tester.tap(find.text('Chèque'));
    await tester.pump();

    expect(find.text('Numéro du chèque'), findsOneWidget);
    expect(find.text('Photographiez le recto, lisible.'), findsOneWidget);
    expect(find.textContaining('1,5 Mo'), findsNothing);
    expect(find.text('Ajouter la photo'), findsOneWidget);
    expect(find.text('Enregistrer le chèque'), findsOneWidget);
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNull);

    await _fill(tester, const Key('check-number'), '104582');
    await _fill(tester, const Key('check-bank'), 'Sogebank');
    await _fill(tester, const Key('check-payer'), 'Marie Joseph');
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNull);

    checkPhotoPicker = () async =>
        const PickedProductPhoto(error: checkPhotoTooHeavyError);
    await tester.ensureVisible(find.byKey(const Key('check-photo')));
    await tester.tap(find.byKey(const Key('check-photo')));
    await tester.pump();
    await tester.pump();
    expect(find.text(checkPhotoTooHeavyError), findsOneWidget);
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNull);

    checkPhotoPicker = () async =>
        PickedProductPhoto(bytes: _tinyPng, mime: 'image/png');
    await tester.ensureVisible(find.byKey(const Key('check-photo')));
    await tester.tap(find.byKey(const Key('check-photo')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('check-photo-preview')), findsOneWidget);
    expect(find.text('Remplacer la photo'), findsOneWidget);
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('clear-check-now')));
    await tester.tap(find.byKey(const Key('clear-check-now')));
    await tester.pump();
    expect(find.text('Compenser le chèque'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear-check-now')));
    await tester.pump();

    await tester.tap(find.text('Enregistrer le chèque'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paiement confirmé !'), findsNothing);
    expect(find.text('Chèque en attente'), findsOneWidget);
    expect(find.textContaining('chèque en attente'), findsWidgets);
    expect(find.text(product.name), findsOneWidget);
    expect(find.text('Sous-total'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('104582'), findsOneWidget);
    expect(find.text('Sogebank'), findsOneWidget);
    expect(find.text('En attente de compensation'), findsOneWidget);
    expect(find.text('Imprimer le reçu'), findsOneWidget);
    expect(find.text('Télécharger le reçu'), findsOneWidget);
    expect(find.text('Envoyer le reçu par WhatsApp'), findsOneWidget);
    expect(find.text('Envoyer le reçu par e-mail'), findsOneWidget);
    expect(find.text('Partager le reçu'), findsOneWidget);
    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
    expect(sale.paymentMethod, PaymentMethodType.check);
    expect(sale.status, RetailOrderStatus.checkPending);
    expect(sale.checkPayment!.cleared, isFalse);
    expect(sale.checkPayment!.number, '104582');
    expect(sale.checkPayment!.bank, 'Sogebank');
    expect(sale.checkPayment!.payerName, 'Marie Joseph');
    expect(sale.checkPayment!.imageBytes, _tinyPng);
    expect(sale.appliesElectronicServiceFee, isFalse);
    expect(sale.lines.single.productName, product.name);
  });

  testWidgets('the clerk can clear the check while recording it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final product = container.read(mockProductsProvider).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: RetailCheckoutWizard(
              cart: [RetailCartEntry(product: product)],
              discountPercent: 0,
              initialStepIndex: 2,
              onSuccess: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Chèque'));
    await tester.pump();
    await _fill(tester, const Key('check-number'), '220011');
    await _fill(tester, const Key('check-bank'), 'Unibank');
    await _fill(tester, const Key('check-payer'), 'Paul Louis');
    checkPhotoPicker = () async =>
        PickedProductPhoto(bytes: _tinyPng, mime: 'image/png');
    await tester.ensureVisible(find.byKey(const Key('check-photo')));
    await tester.tap(find.byKey(const Key('check-photo')));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('clear-check-now')));
    await tester.tap(find.byKey(const Key('clear-check-now')));
    await tester.pump();
    await tester.tap(find.text('Compenser le chèque'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paiement confirmé !'), findsOneWidget);
    expect(find.text('Chèque en attente'), findsNothing);
    expect(find.textContaining('payée'), findsOneWidget);
    expect(find.text('Chèque compensé'), findsOneWidget);
    expect(find.text('Imprimer le reçu'), findsOneWidget);
    expect(find.text('Partager le reçu'), findsOneWidget);
    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
    expect(sale.status, RetailOrderStatus.paid);
    expect(sale.checkPayment!.cleared, isTrue);
    expect(sale.checkPayment!.clearedAt, isNotNull);
    expect(sale.checkPayment!.number, '220011');
  });

  testWidgets('approving a pending check marks the order paid', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final order = RetailOrder(
      id: 'pos-check',
      orderNumber: 'ORD-2026-0091',
      clientName: 'Marie Joseph',
      status: RetailOrderStatus.checkPending,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.check,
      checkPayment: RetailCheckPayment(
        number: '104582',
        bank: 'Sogebank',
        payerName: 'Jean Pierre',
        date: DateTime(2026, 10, 22),
        imageDataUrl: RetailCheckPayment.dataUrlFor(_tinyPng, 'image/png'),
      ),
      lines: const [
        RetailOrderLine(
          productName: 'Riz Blanc 25kg',
          productId: 1,
          quantity: 1,
          unitPriceHtg: 3200,
        ),
      ],
      createdAt: DateTime(2026, 10, 22, 11, 0),
      paidAt: DateTime(2026, 10, 22, 11, 0),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(retailOrdersProvider.notifier).add(order);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: RetailOrderDetailPage(order: order),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ORD-2026-0091'), findsWidgets);
    expect(find.text('Chèque'), findsOneWidget);
    expect(find.text('104582'), findsOneWidget);
    expect(find.text('Sogebank'), findsOneWidget);
    expect(find.text('Jean Pierre'), findsOneWidget);
    expect(find.text('22/10/2026'), findsOneWidget);
    expect(find.byKey(const Key('check-payment-photo')), findsOneWidget);
    expect(find.text('En attente de compensation'), findsOneWidget);
    expect(find.text('Approuver le chèque'), findsOneWidget);
    expect(find.text('Marquer terminé'), findsNothing);
    expect(find.text('Commande introuvable'), findsNothing);

    await tester.tap(find.text('Approuver le chèque'));
    await tester.pump();
    await tester.pump();

    final saved = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(saved.status, RetailOrderStatus.paid);
    expect(saved.checkPayment!.cleared, isTrue);
    expect(find.text('Chèque compensé'), findsOneWidget);
    expect(find.text('Approuver le chèque'), findsNothing);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('Marquer terminé'), findsOneWidget);
  });
}

ElevatedButton _confirm(WidgetTester tester, String label) {
  return tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, label),
  );
}

Future<void> _fill(WidgetTester tester, Key key, String value) async {
  await tester.enterText(
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    value,
  );
  await tester.pump();
}

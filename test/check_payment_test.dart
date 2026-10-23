import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/mock/mock_retail_orders.dart';
import 'package:retail_pos/core/models/customer.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/providers/auth_provider.dart';
import 'package:retail_pos/retail/receipt/sale_receipt_text.dart';
import 'package:retail_pos/core/utils/operator_name.dart';
import 'package:retail_pos/core/models/retail_check_payment.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/screens/customers/customer_detail_screen.dart';
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
    expect(restored.checkPayment!.amountHtg, isNull);
    expect(restored.checkPayment!.creditPosted, isFalse);
    expect(restored.checkPayment!.refused, isFalse);
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

    final named = RetailCheckPayment.compose(
      number: '104582',
      bank: 'Sogebank',
      payerName: 'Marie',
      date: DateTime(2026, 10, 22),
      photo: _tinyPng,
      mime: 'image/png',
      cleared: true,
      clearedBy: ' Nadia Pierre ',
    )!;
    expect(named.clearedBy, 'Nadia Pierre');
    expect(named.clearanceLabel, 'Chèque compensé par : Nadia Pierre');
    expect(
      RetailCheckPayment.fromJson(named.toJson())!.clearedBy,
      'Nadia Pierre',
    );
    expect(
      RetailCheckPayment.compose(
        number: '104582',
        bank: 'Sogebank',
        payerName: 'Marie',
        date: DateTime(2026, 10, 22),
        photo: _tinyPng,
        mime: 'image/png',
        clearedBy: 'Nadia Pierre',
      )!.clearedBy,
      isNull,
    );
    expect(
      currentOperatorName(staffName: 'Alice', accountName: 'Bob'),
      'Alice',
    );
    expect(currentOperatorName(accountName: 'Bob'), 'Bob');
    expect(currentOperatorName(), 'Gérant');
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
    await tester.tap(find.byKey(const Key('check-photo-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-photo-viewer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-photo-zoom-in')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('check-photo-close')),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-photo-viewer')), findsNothing);
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
    container
        .read(authProvider.notifier)
        .login(
          userName: 'Nadia Pierre',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
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
    expect(find.text('Chèque compensé par : Nadia Pierre'), findsOneWidget);
    expect(find.text('Imprimer le reçu'), findsOneWidget);
    expect(find.text('Partager le reçu'), findsOneWidget);
    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
    expect(sale.status, RetailOrderStatus.paid);
    expect(sale.checkPayment!.cleared, isTrue);
    expect(sale.checkPayment!.clearedAt, isNotNull);
    expect(sale.checkPayment!.clearedBy, 'Nadia Pierre');
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
    container
        .read(authProvider.notifier)
        .login(
          userName: 'Marc Joseph',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
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
    await tester.ensureVisible(find.byKey(const Key('check-payment-photo')));
    await tester.tap(find.byKey(const Key('check-payment-photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-photo-viewer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-photo-zoom-in')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('check-photo-close')),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-photo-viewer')), findsNothing);
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
    expect(saved.checkPayment!.clearedBy, 'Marc Joseph');
    expect(find.text('Chèque compensé par : Marc Joseph'), findsOneWidget);
    expect(find.text('Approuver le chèque'), findsNothing);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('Marquer terminé'), findsOneWidget);
    expect(find.text('Modifier le chèque'), findsOneWidget);
  });

  test('a short check reserves credit until it is compensated', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(customerProvider).balanceFor('c6');
    final order = _shortOrder(amount: 1000, due: 500);
    container.read(retailOrdersProvider.notifier).add(order);

    final pending = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(saleReceiptCheckPending(pending), isTrue);
    expect(saleReceiptBalanceLabel(pending), 'Solde en attente de crédit');
    expect(saleReceiptPaidLabel(pending), 'Montant du chèque');
    expect(container.read(customerProvider).balanceFor('c6'), before);

    final blocked = container
        .read(retailOrdersProvider.notifier)
        .clearCheck('missing');
    expect(blocked, isNull);

    container
        .read(customerProvider.notifier)
        .addCustomer(
          Customer(
            id: 'tight',
            name: 'Limite Basse',
            phone: '+509 3000-1111',
            creditLimitHtg: 100,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    final tight = _shortOrder(
      id: 'pos-tight',
      amount: 50,
      due: 150,
      customerId: 'tight',
    );
    container.read(retailOrdersProvider.notifier).add(tight);
    expect(
      container.read(retailOrdersProvider.notifier).clearCheck(tight.id),
      'La limite de crédit sera dépassée.',
    );
    expect(
      container
          .read(retailOrdersProvider)
          .firstWhere((row) => row.id == tight.id)
          .checkPayment!
          .cleared,
      isFalse,
    );

    container
        .read(customerProvider.notifier)
        .addCustomer(
          Customer(
            id: 'room',
            name: 'Marge Crédit',
            phone: '+509 3000-2222',
            creditLimitHtg: 200,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    final room = _shortOrder(
      id: 'pos-room',
      amount: 150,
      due: 150,
      customerId: 'room',
    );
    container.read(retailOrdersProvider.notifier).add(room);
    expect(
      container
          .read(retailOrdersProvider.notifier)
          .updateCheck(
            orderId: room.id,
            amountHtg: 120,
            number: '1000',
            bank: 'Sogebank',
            payerName: 'Marge Crédit',
            date: DateTime(2026, 10, 23),
            creditCustomerId: 'room',
          ),
      isNull,
    );
    expect(
      container
          .read(retailOrdersProvider)
          .firstWhere((row) => row.id == room.id)
          .unpaidBalanceHtg,
      180,
    );
    expect(container.read(customerProvider).balanceFor('room'), 0);
    expect(
      container
          .read(retailOrdersProvider.notifier)
          .updateCheck(
            orderId: room.id,
            amountHtg: 50,
            number: '1000',
            bank: 'Sogebank',
            payerName: 'Marge Crédit',
            date: DateTime(2026, 10, 23),
            creditCustomerId: 'room',
          ),
      'La limite de crédit sera dépassée.',
    );

    final refusedCustomer = _shortOrder(
      id: 'pos-blocked',
      amount: 50,
      due: 100,
      customerId: 'c4',
    );
    container.read(retailOrdersProvider.notifier).add(refusedCustomer);
    expect(
      container
          .read(retailOrdersProvider.notifier)
          .clearCheck(refusedCustomer.id),
      'Rosnel Dupont est bloqué.',
    );

    expect(
      container.read(retailOrdersProvider.notifier).clearCheck(order.id),
      isNull,
    );
    final cleared = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(cleared.status, RetailOrderStatus.partiallyPaid);
    expect(cleared.checkPayment!.cleared, isTrue);
    expect(cleared.checkPayment!.creditPosted, isTrue);
    expect(
      container.read(customerProvider).balanceFor('c6'),
      closeTo(before + 500, 0.01),
    );
    expect(saleReceiptBalanceLabel(cleared), 'Solde au crédit');
    expect(saleReceiptPaidLabel(cleared), 'Payé');

    expect(
      container
          .read(retailOrdersProvider.notifier)
          .updateCheck(
            orderId: order.id,
            amountHtg: 1200,
            number: '1000',
            bank: 'Sogebank',
            payerName: 'Sophie Laurent',
            date: DateTime(2026, 10, 23),
            creditCustomerId: 'c6',
          ),
      isNull,
    );
    expect(
      container.read(customerProvider).balanceFor('c6'),
      closeTo(before + 300, 0.01),
    );
    expect(
      container
          .read(retailOrdersProvider.notifier)
          .updateCheck(
            orderId: order.id,
            amountHtg: 1400,
            number: '1000',
            bank: 'Unibank',
            payerName: 'Sophie Laurent',
            date: DateTime(2026, 10, 23),
            creditCustomerId: 'c6',
          ),
      isNull,
    );
    final adjusted = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(adjusted.unpaidBalanceHtg, 100);
    expect(adjusted.checkPayment!.bank, 'Unibank');
    expect(
      container.read(customerProvider).balanceFor('c6'),
      closeTo(before + 100, 0.01),
    );

    container.read(retailOrdersProvider.notifier).refuseCheck(tight.id);
    final dropped = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == tight.id);
    expect(dropped.checkPayment!.refused, isTrue);
    expect(dropped.checkPayment!.clearanceLabel, 'Chèque refusé');
    expect(dropped.balanceDueHtg, 200);
    expect(dropped.amountPaidHtg, 0);
    expect(saleReceiptCheckPending(dropped), isFalse);
    expect(saleReceiptBalanceLabel(dropped), 'Solde impayé');
    expect(container.read(customerProvider).balanceFor('tight'), 0);
    expect(
      container
          .read(retailOrdersProvider.notifier)
          .updateCheck(
            orderId: tight.id,
            amountHtg: 100,
            number: '1000',
            bank: 'Sogebank',
            payerName: 'Limite Basse',
            date: DateTime(2026, 10, 23),
          ),
      'Ce chèque a été refusé.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  testWidgets('a short check asks for a client and waits to post the credit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(authProvider.notifier)
        .login(
          userName: 'Nadia Pierre',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
    final before = container.read(customerProvider).balanceFor('c6');
    final product = container.read(mockProductsProvider).first;
    checkPhotoPicker = () async =>
        PickedProductPhoto(bytes: _tinyPng, mime: 'image/png');

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

    await _fill(tester, const Key('check-number'), '1000');
    await _fill(tester, const Key('check-bank'), 'Sogebank');
    await _fill(tester, const Key('check-payer'), 'Sophie Laurent');
    await tester.ensureVisible(find.byKey(const Key('check-photo')));
    await tester.tap(find.byKey(const Key('check-photo')));
    await tester.pump();
    await tester.pump();
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNotNull);

    await _fill(tester, const Key('check-amount'), '100');
    await tester.pump();
    expect(find.byKey(const Key('check-balance-warning')), findsOneWidget);
    expect(find.textContaining('en attente de crédit'), findsOneWidget);
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('cash-credit-search')));
    await tester.enterText(
      find.byKey(const Key('cash-credit-search')),
      'Sophie',
    );
    await tester.pump();
    final sophie = find.widgetWithText(ListTile, 'Sophie Laurent');
    await tester.ensureVisible(sophie);
    await tester.tap(sophie);
    await tester.pump();
    expect(_confirm(tester, 'Enregistrer le chèque').onPressed, isNotNull);

    await tester.tap(find.text('Enregistrer le chèque'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paiement confirmé !'), findsNothing);
    expect(find.text('Chèque en attente'), findsOneWidget);
    expect(find.text('Montant du chèque'), findsOneWidget);
    final checkAmountLabel = tester.widget<Text>(
      find.text('Montant du chèque'),
    );
    expect(checkAmountLabel.style?.fontWeight, FontWeight.w700);
    final checkAmountValue = tester.widget<Text>(
      find
          .descendant(
            of: find
                .ancestor(
                  of: find.text('Montant du chèque'),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byType(Text),
          )
          .last,
    );
    expect(checkAmountValue.style?.fontWeight, FontWeight.w700);
    expect(find.text('Solde en attente de crédit'), findsOneWidget);
    expect(find.text('Solde au crédit'), findsNothing);
    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
    expect(sale.status, RetailOrderStatus.checkPending);
    expect(sale.amountPaidHtg, 100);
    expect(sale.balanceDueHtg, greaterThan(100));
    expect(sale.checkPayment!.amountHtg, 100);
    expect(sale.checkPayment!.creditCustomerId, 'c6');
    expect(sale.checkPayment!.creditPosted, isFalse);
    expect(container.read(customerProvider).balanceFor('c6'), before);

    expect(
      container.read(retailOrdersProvider.notifier).clearCheck(sale.id),
      isNull,
    );
    final cleared = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id == sale.id);
    expect(cleared.status, RetailOrderStatus.partiallyPaid);
    expect(cleared.checkPayment!.cleared, isTrue);
    expect(cleared.checkPayment!.creditPosted, isTrue);
    expect(
      container.read(customerProvider).balanceFor('c6'),
      closeTo(before + sale.balanceDueHtg!, 0.01),
    );
  });

  testWidgets('the check can be corrected after it was recorded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(authProvider.notifier)
        .login(
          userName: 'Marc Joseph',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
    final before = container.read(customerProvider).balanceFor('c6');
    final order = _shortOrder(amount: 1000, due: 500);
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

    expect(find.text('Solde en attente de crédit'), findsOneWidget);
    expect(find.text('Modifier le chèque'), findsOneWidget);
    expect(find.text('Refuser le chèque'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-check')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getSize(find.byKey(const Key('edit-check-panel'))).width,
      480,
    );
    await _fill(tester, const Key('edit-check-number'), '2000');
    await _fill(tester, const Key('edit-check-amount'), '1200');
    await tester.pump();
    expect(find.byKey(const Key('edit-check-balance')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-check-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2000'), findsWidgets);
    expect(container.read(customerProvider).balanceFor('c6'), before);
    final edited = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(edited.checkPayment!.number, '2000');
    expect(edited.amountPaidHtg, 1200);
    expect(edited.balanceDueHtg, 300);
    expect(edited.checkPayment!.creditPosted, isFalse);

    await tester.tap(find.text('Refuser le chèque'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refuse-check-confirm')));
    await tester.pump();
    await tester.pump();

    final refused = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(refused.checkPayment!.refused, isTrue);
    expect(refused.balanceDueHtg, 1500);
    expect(container.read(customerProvider).balanceFor('c6'), before);
    expect(find.text('Chèque refusé'), findsOneWidget);
    expect(find.text('Modifier le chèque'), findsNothing);
    expect(find.text('Solde impayé'), findsOneWidget);
  });

  testWidgets('a balance transaction opens the sale receipt', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authProvider.notifier).login(
          userName: 'Gérant',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
    final order = _shortOrder(amount: 200, due: 448);
    container.read(retailOrdersProvider.notifier).add(order);
    container.read(customerProvider.notifier).postCharge(
          customerId: 'c6',
          amountHtg: 448,
          cashierName: 'Gérant',
          linkedOrderId: order.id,
          description:
              'Solde du chèque ${order.orderNumber} après compensation',
        );
    final customer = container
        .read(customerProvider)
        .customers
        .firstWhere((row) => row.id == 'c6');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CustomerDetailPanel(
              customer: customer,
              isDark: false,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Lunch'));
    await tester.tap(find.text('Lunch'));
    await tester.pump();
    expect(find.byKey(const Key('linked-sale-receipt')), findsNothing);

    final charge = find.textContaining('Solde du chèque');
    await tester.ensureVisible(charge);
    await tester.tap(charge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('linked-sale-receipt')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('linked-sale-receipt'))).width,
      390,
    );
    expect(find.text('Reçu'), findsOneWidget);
    expect(find.text('Chèque en attente'), findsOneWidget);
    expect(find.text('Montant du chèque'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('Sogebank'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('linked-sale-receipt')),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('linked-sale-receipt')), findsNothing);
  });
}

ElevatedButton _confirm(WidgetTester tester, String label) {
  return tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, label),
  );
}

RetailOrder _shortOrder({
  String id = 'pos-short',
  required double amount,
  required double due,
  String customerId = 'c6',
}) {
  return RetailOrder(
    id: id,
    orderNumber: 'ORD-$id',
    clientName: 'Sophie Laurent',
    clientPhone: '+509 3711-3344',
    status: RetailOrderStatus.checkPending,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.check,
    amountPaidHtg: amount,
    balanceDueHtg: due,
    checkPayment: RetailCheckPayment(
      number: '1000',
      bank: 'Sogebank',
      payerName: 'Sophie Laurent',
      date: DateTime(2026, 10, 23),
      imageDataUrl: RetailCheckPayment.dataUrlFor(_tinyPng, 'image/png'),
      amountHtg: amount,
      creditCustomerId: customerId,
    ),
    lines: const [
      RetailOrderLine(
        productName: 'Riz',
        productId: 1,
        quantity: 1,
        unitPriceHtg: 1000,
      ),
    ],
    createdAt: DateTime(2026, 10, 23),
    paidAt: DateTime(2026, 10, 23),
  );
}

Future<void> _fill(WidgetTester tester, Key key, String value) async {
  await tester.enterText(
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    value,
  );
  await tester.pump();
}

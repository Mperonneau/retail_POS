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
import 'package:retail_pos/core/models/retail_fulfillment_mode.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/providers/auth_provider.dart';
import 'package:retail_pos/core/screens/order_history/order_history_screen.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/retail/models/retail_cart_entry.dart';
import 'package:retail_pos/retail/screens/checkout_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  Future<ProviderContainer> openRegister(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
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
    return container;
  }

  Future<void> enterCash(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(const Key('cash-received')), value);
    await tester.pump();
  }

  ElevatedButton confirmButton(WidgetTester tester) {
    return tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirmer le paiement'),
    );
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Confirmer le paiement'));
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  RetailOrder latestSale(ProviderContainer container) {
    return container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
  }

  testWidgets('an empty cash field is still a full payment', (tester) async {
    final container = await openRegister(tester);
    expect(find.byKey(const Key('cash-balance-warning')), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    expect(find.text('Paiement confirmé !'), findsOneWidget);
    expect(find.text('Paiement partiel'), findsNothing);
    expect(find.text('Solde impayé'), findsNothing);
    final sale = latestSale(container);
    expect(sale.status, RetailOrderStatus.paid);
    expect(sale.amountPaidHtg, isNull);
    expect(sale.unpaidBalanceHtg, 0);
  });

  testWidgets('cash below the total warns and marks the order partially paid', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await enterCash(tester, '100');

    expect(find.byKey(const Key('cash-balance-warning')), findsOneWidget);
    expect(find.textContaining('partiellement payée'), findsOneWidget);
    expect(find.text('Monnaie'), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    expect(find.text('Paiement partiel'), findsOneWidget);
    expect(find.text('Paiement confirmé !'), findsNothing);
    expect(find.text('Solde impayé'), findsOneWidget);
    expect(find.byKey(const Key('receipt-balance-due')), findsOneWidget);
    expect(find.textContaining('partiellement payée'), findsWidgets);
    final sale = latestSale(container);
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    expect(sale.status.label, 'Partiellement payée');
    expect(sale.amountPaidHtg, 100);
    expect(sale.balanceDueHtg, 3740);
    expect(sale.paymentMethod, PaymentMethodType.cash);
    expect(
      container
          .read(customerProvider)
          .transactions
          .where((tx) => tx.linkedOrderId == sale.id),
      isEmpty,
    );
  });

  testWidgets('more cash than the total is change, not a balance', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await enterCash(tester, '10000');

    expect(find.text('Monnaie'), findsOneWidget);
    expect(find.byKey(const Key('cash-balance-warning')), findsNothing);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.status, RetailOrderStatus.paid);
    expect(sale.amountPaidHtg, isNull);
    expect(find.text('Paiement confirmé !'), findsOneWidget);
    expect(find.text('Solde impayé'), findsNothing);
  });

  testWidgets('saving the balance as credit requires a client', (tester) async {
    final container = await openRegister(tester);
    await enterCash(tester, '100');
    await tester.ensureVisible(find.byKey(const Key('save-balance-as-credit')));
    await tester.tap(find.byKey(const Key('save-balance-as-credit')));
    await tester.pump();

    expect(confirmButton(tester).onPressed, isNull);
    expect(find.text('Nouveau client'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('cash-credit-search')),
      'Sophie',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Sophie Laurent'));
    await tester.tap(find.text('Sophie Laurent'));
    await tester.pump();

    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.textContaining('Solde à porter au compte'), findsOneWidget);
    final balanceBefore = container.read(customerProvider).balanceFor('c6');

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    expect(sale.clientName, 'Sophie Laurent');
    expect(sale.amountPaidHtg, 100);
    expect(sale.balanceDueHtg, 3740);
    expect(find.text('Solde impayé'), findsOneWidget);
    final tx = container
        .read(customerProvider)
        .transactions
        .where((row) => row.linkedOrderId == sale.id)
        .single;
    expect(tx.paidAmountHtg, 100);
    expect(tx.amountHtg, 3840);
    expect(tx.creditedHtg, 3740);
    expect(tx.cashierName, 'Nadia Pierre');
    expect(tx.description, contains(sale.orderNumber));
    expect(
      container.read(customerProvider).balanceFor('c6'),
      balanceBefore + 3740,
    );
  });

  testWidgets('a credit limit blocks the partial payment', (tester) async {
    final container = await openRegister(tester);
    container
        .read(customerProvider.notifier)
        .addCustomer(
          Customer(
            id: 'cust-limit',
            name: 'Limite Basse',
            phone: '+509 1111-2222',
            creditLimitHtg: 1,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    await enterCash(tester, '100');
    await tester.ensureVisible(find.byKey(const Key('save-balance-as-credit')));
    await tester.tap(find.byKey(const Key('save-balance-as-credit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('cash-credit-search')),
      'Limite Basse',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Limite Basse'));
    await tester.pump();

    expect(find.text('La limite de crédit sera dépassée.'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('the cashier can create the client who will owe the balance', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await enterCash(tester, '500');
    await tester.ensureVisible(find.byKey(const Key('save-balance-as-credit')));
    await tester.tap(find.byKey(const Key('save-balance-as-credit')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('cash-credit-new')));
    await tester.tap(find.byKey(const Key('cash-credit-new')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('cash-credit-name')),
      'Paul Louis',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('cash-credit-phone')),
        matching: find.byType(EditableText),
      ),
      '37001234',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('cash-credit-create')));
    await tester.tap(find.byKey(const Key('cash-credit-create')));
    await tester.pump();

    expect(find.text('Paul Louis'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.clientName, 'Paul Louis');
    expect(sale.clientPhone, contains('37001234'));
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    expect(sale.amountPaidHtg, 500);
    expect(sale.balanceDueHtg, 3340);
    final customer = container
        .read(customerProvider)
        .customers
        .firstWhere((row) => row.name == 'Paul Louis');
    expect(container.read(customerProvider).balanceFor(customer.id), 3340);
  });

  testWidgets('a blocked client cannot take the balance', (tester) async {
    await openRegister(tester);
    await enterCash(tester, '100');
    await tester.ensureVisible(find.byKey(const Key('save-balance-as-credit')));
    await tester.tap(find.byKey(const Key('save-balance-as-credit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('cash-credit-search')),
      'Rosnel',
    );
    await tester.pump();
    expect(find.textContaining('BLOQUÉ'), findsOneWidget);
    await tester.tap(find.text('Rosnel Dupont'));
    await tester.pump();

    expect(find.text('Retirer'), findsNothing);
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('the order page shows the unpaid balance and stays open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final order = RetailOrder(
      id: 'pos-partial',
      orderNumber: 'ORD-2026-4610',
      clientName: 'Sophie Laurent',
      status: RetailOrderStatus.partiallyPaid,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.cash,
      fulfillmentMode: RetailFulfillmentMode.pickup,
      amountPaidHtg: 100,
      balanceDueHtg: 3740,
      lines: const [
        RetailOrderLine(
          productName: 'Riz Blanc 25kg',
          productId: 1,
          quantity: 1,
          unitPriceHtg: 3200,
        ),
      ],
      createdAt: DateTime(2026, 10, 22, 11),
      paidAt: DateTime(2026, 10, 22, 11),
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

    expect(find.text('Partiellement payée'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('order-balance-due')));
    expect(find.text('Solde impayé'), findsOneWidget);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.textContaining('Encaissé le'), findsOneWidget);
    expect(find.text('Marquer prêt'), findsNothing);
    expect(find.text('Marquer terminé'), findsOneWidget);
  });
}

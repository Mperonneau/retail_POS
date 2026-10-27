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
import 'package:retail_pos/core/permissions/client_credit_grant.dart';
import 'package:retail_pos/core/providers/auth_provider.dart';
import 'package:retail_pos/core/providers/permission_settings_provider.dart';
import 'package:retail_pos/core/providers/staff_directory_provider.dart';
import 'package:retail_pos/core/providers/staff_session_provider.dart';
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

  Future<ProviderContainer> openRegister(
    WidgetTester tester, {
    int initialStepIndex = 2,
  }) async {
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
              initialStepIndex: initialStepIndex,
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

  testWidgets('a paid retrait order is marked terminé', (tester) async {
    final container = await openRegister(tester, initialStepIndex: 0);
    await tester.ensureVisible(find.text('Retrait'));
    await tester.tap(find.text('Retrait'));
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Payer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(confirmButton(tester).onPressed, isNull);
    await enterCash(tester, '100000');
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.fulfillmentMode, RetailFulfillmentMode.pickup);
    expect(sale.status, RetailOrderStatus.completed);
    expect(sale.status.label, 'Terminé');
  });

  testWidgets('an empty cash field keeps Confirmer le paiement off', (
    tester,
  ) async {
    final container = await openRegister(tester);
    expect(find.byKey(const Key('cash-balance-warning')), findsNothing);
    expect(confirmButton(tester).onPressed, isNull);

    await confirm(tester);

    expect(find.text('Paiement confirmé !'), findsNothing);
    expect(
      container
          .read(retailOrdersProvider)
          .where((order) => order.id.startsWith('pos-')),
      isEmpty,
    );
  });

  testWidgets('cash below the total warns and marks the order partially paid', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await enterCash(tester, '100');

    expect(find.byKey(const Key('cash-balance-warning')), findsOneWidget);
    expect(find.textContaining('Montant insuffisant'), findsOneWidget);
    expect(find.textContaining('Solde restant'), findsOneWidget);
    expect(find.text('Monnaie'), findsNothing);
    expect(find.text('Nouveau client'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull);
    expect(
      container
          .read(retailOrdersProvider)
          .where((order) => order.id.startsWith('pos-')),
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

  test('credit grant follows the role, and a shop account is allowed', () {
    final settings = PermissionSettingsState.initial();
    expect(
      employeeCanGrantClientCredit(
        employeeId: 'seed_1',
        role: StaffRole.admin,
        module: ActiveModule.retail,
        settings: settings,
      ),
      isTrue,
    );
    expect(
      employeeCanGrantClientCredit(
        employeeId: 'seed_4',
        role: StaffRole.cashier,
        module: ActiveModule.retail,
        settings: settings,
      ),
      isFalse,
    );
    expect(
      employeeCanGrantClientCredit(
        employeeId: 'seed_2',
        role: StaffRole.seller,
        module: ActiveModule.retail,
        settings: settings,
      ),
      isFalse,
    );
    expect(
      currentUserCanGrantClientCredit(
        session: null,
        shopAccountSignedIn: true,
        module: ActiveModule.retail,
        settings: settings,
      ),
      isTrue,
    );
    final directory = StaffDirectoryNotifier().state;
    final seller = lookupStaffByPin('1111', directory);
    final admin = lookupStaffByPin('3333', directory);
    expect(seller?.name, 'Marie-Carmel Joseph');
    expect(admin?.role, StaffRole.admin);
    expect(lookupStaffByPin('0000', directory), isNull);
  });

  testWidgets('a searched client is reused for the balance', (tester) async {
    final container = await openRegister(tester, initialStepIndex: 0);
    await tester.enterText(
      find.byKey(const Key('checkout-client-search')),
      'Jean-Baptiste',
    );
    await tester.pump();
    await tester.tap(find.text('Jean-Baptiste Michel'));
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.tap(find.text('Payer'));
    await tester.pump();
    await enterCash(tester, '100');

    expect(find.text('Jean-Baptiste Michel'), findsWidgets);
    expect(find.text('Un compte sera créé pour ce client.'), findsOneWidget);
    expect(find.byKey(const Key('cash-credit-search')), findsNothing);
    expect(find.byKey(const Key('cash-balance-phone')), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.clientName, 'Jean-Baptiste Michel');
    expect(sale.clientPhone, contains('3789'));
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    final customer = container
        .read(customerProvider)
        .customers
        .firstWhere((row) => row.name == 'Jean-Baptiste Michel');
    expect(customer.phone, contains('3789'));
    expect(container.read(customerProvider).balanceFor(customer.id), 3740);
  });

  testWidgets('a typed client name only asks for the phone', (tester) async {
    final container = await openRegister(tester, initialStepIndex: 0);
    await tester.enterText(
      find.byKey(const Key('checkout-client-name')),
      'Claire Denis',
    );
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.tap(find.text('Payer'));
    await tester.pump();
    await enterCash(tester, '100');

    expect(find.text('Claire Denis'), findsWidgets);
    expect(find.byKey(const Key('cash-balance-phone')), findsOneWidget);
    expect(find.byKey(const Key('cash-credit-name')), findsNothing);
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('cash-balance-phone')),
        matching: find.byType(EditableText),
      ),
      '37001234',
    );
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.clientName, 'Claire Denis');
    expect(sale.clientPhone, contains('37001234'));
    expect(sale.status, RetailOrderStatus.partiallyPaid);
  });

  testWidgets('a seller needs an authorized PIN to save the balance', (
    tester,
  ) async {
    final container = await openRegister(tester);
    expect(
      container.read(staffSessionProvider.notifier).signInWithPin('1111'),
      isNull,
    );
    await enterCash(tester, '100');
    await tester.enterText(
      find.byKey(const Key('cash-credit-search')),
      'Sophie',
    );
    await tester.pump();
    await tester.tap(find.text('Sophie Laurent'));
    await tester.pump();
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Autorisation'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('credit-grant-pin')), '1111');
    await tester.tap(find.text('Autoriser'));
    await tester.pump();
    expect(
      find.text('Cette personne ne peut pas accorder un crédit.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('credit-grant-pin')), '3333');
    await tester.tap(find.text('Autoriser'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sale = latestSale(container);
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    expect(sale.clientName, 'Sophie Laurent');
    final tx = container
        .read(customerProvider)
        .transactions
        .where((row) => row.linkedOrderId == sale.id)
        .single;
    expect(tx.description, contains('Autorisé par Jean-Marc Dupont'));
    container.read(staffSessionProvider.notifier).clear();
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

  Future<void> enterCheckoutPhone(WidgetTester tester, String digits) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('checkout-client-phone')),
        matching: find.byType(EditableText),
      ),
      digits,
    );
    await tester.pump();
  }

  testWidgets('a searched client becomes a card until it is removed', (
    tester,
  ) async {
    await openRegister(tester, initialStepIndex: 0);
    expect(find.text('Téléphone (facultatif)'), findsOneWidget);
    expect(find.byKey(const Key('checkout-client-name')), findsOneWidget);
    expect(find.byKey(const Key('checkout-client-search')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('checkout-client-search'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('checkout-client-name'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('checkout-client-name'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('checkout-client-phone'))).dy,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('checkout-client-search')),
      'Madame Pierre',
    );
    await tester.pump();
    await tester.tap(find.text('Boutique Madame Pierre'));
    await tester.pump();

    expect(find.byKey(const Key('checkout-selected-client')), findsOneWidget);
    expect(find.text('Boutique Madame Pierre'), findsOneWidget);
    expect(find.text('+509 3456-7890'), findsOneWidget);
    expect(find.byKey(const Key('checkout-client-name')), findsNothing);
    expect(find.byKey(const Key('checkout-client-search')), findsNothing);
    expect(find.byKey(const Key('checkout-client-phone')), findsNothing);
    expect(find.text('Téléphone (facultatif)'), findsNothing);

    await tester.tap(find.text('Livraison'));
    await tester.pump();
    expect(find.byKey(const Key('checkout-client-phone')), findsNothing);
    expect(find.text('Téléphone *'), findsNothing);

    await tester.tap(find.text('En magasin'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkout-client-clear')));
    await tester.pump();

    expect(find.byKey(const Key('checkout-selected-client')), findsNothing);
    expect(find.byKey(const Key('checkout-client-name')), findsOneWidget);
    expect(find.byKey(const Key('checkout-client-search')), findsOneWidget);
    expect(find.text('+509 3456-7890'), findsNothing);
    expect(find.text('Téléphone (facultatif)'), findsOneWidget);
    final cleared = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('checkout-client-phone')),
        matching: find.byType(EditableText),
      ),
    );
    expect(cleared.controller.text, isEmpty);
  });

  testWidgets('a typed name keeps the fields and an optional phone', (
    tester,
  ) async {
    await openRegister(tester, initialStepIndex: 0);
    await tester.enterText(
      find.byKey(const Key('checkout-client-name')),
      'Claire Denis',
    );
    await tester.pump();
    await tester.tap(find.text('Retrait'));
    await tester.pump();

    expect(find.byKey(const Key('checkout-client-name')), findsOneWidget);
    expect(find.byKey(const Key('checkout-client-search')), findsOneWidget);
    expect(find.byKey(const Key('checkout-selected-client')), findsNothing);
    expect(find.text('Téléphone (facultatif)'), findsOneWidget);
    expect(find.text('Téléphone *'), findsNothing);

    await tester.tap(find.text('Suivant'));
    await tester.pump();
    expect(find.text('Récapitulatif'), findsOneWidget);
  });

  testWidgets('delivery requires the phone and does not ask for it twice', (
    tester,
  ) async {
    await openRegister(tester, initialStepIndex: 0);
    await tester.tap(find.text('Livraison'));
    await tester.pump();

    expect(find.text('Téléphone *'), findsOneWidget);
    expect(find.text('Téléphone (facultatif)'), findsNothing);
    expect(find.text('Lieu *'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(
        'L\'adresse et le téléphone sont obligatoires pour la livraison.',
      ),
      findsOneWidget,
    );
    expect(find.text('Client et livraison'), findsOneWidget);

    await enterCheckoutPhone(tester, '34567890');
    ScaffoldMessenger.of(
      tester.element(find.text('Client et livraison')),
    ).hideCurrentSnackBar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Récapitulatif'), findsNothing);
    expect(find.text('Client et livraison'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('checkout-delivery-place')),
        matching: find.byType(EditableText),
      ),
      'Pétion-Ville',
    );
    await tester.pump();
    ScaffoldMessenger.of(
      tester.element(find.text('Client et livraison')),
    ).hideCurrentSnackBar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    expect(find.text('Récapitulatif'), findsOneWidget);
    expect(find.textContaining('34567890'), findsWidgets);
  });

  testWidgets('a phone typed with the name is reused for the balance', (
    tester,
  ) async {
    final container = await openRegister(tester, initialStepIndex: 0);
    await tester.enterText(
      find.byKey(const Key('checkout-client-name')),
      'Claire Denis',
    );
    await enterCheckoutPhone(tester, '37001234');
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.tap(find.text('Payer'));
    await tester.pump();
    await enterCash(tester, '100');

    expect(find.text('Claire Denis'), findsWidgets);
    expect(find.byKey(const Key('cash-balance-phone')), findsNothing);
    expect(find.byKey(const Key('cash-credit-search')), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await confirm(tester);

    final sale = latestSale(container);
    expect(sale.clientName, 'Claire Denis');
    expect(sale.clientPhone, contains('37001234'));
    expect(sale.status, RetailOrderStatus.partiallyPaid);
    final customer = container
        .read(customerProvider)
        .customers
        .firstWhere((row) => row.name == 'Claire Denis');
    expect(customer.phone, contains('37001234'));
  });
}

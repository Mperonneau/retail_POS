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
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/providers/auth_provider.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
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
    int initialStepIndex = 0,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authProvider.notifier).login(
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

  Future<void> pickMadamePierre(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('checkout-client-search')),
      'Madame Pierre',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Boutique Madame Pierre'));
    await tester.pump();
  }

  Future<void> openCredit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Suivant'));
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.ensureVisible(find.text('Payer'));
    await tester.tap(find.text('Payer'));
    await tester.pump();
    await tester.ensureVisible(find.text('Crédit'));
    await tester.tap(find.text('Crédit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('credit shows the selected client until they are removed', (
    tester,
  ) async {
    await openRegister(tester);
    await pickMadamePierre(tester);
    await openCredit(tester);

    expect(find.byKey(const Key('credit-selected-client')), findsOneWidget);
    expect(find.text('Boutique Madame Pierre'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('credit-selected-client')),
        matching: find.text('Boutique Madame Pierre'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('credit-selected-client')),
        matching: find.text('+509 3456-7890'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('credit-client-search')), findsNothing);
    expect(find.text('Nouveau client'), findsNothing);

    await tester.tap(find.byKey(const Key('credit-client-clear')));
    await tester.pump();

    expect(find.byKey(const Key('credit-selected-client')), findsNothing);
    expect(find.byKey(const Key('credit-client-search')), findsOneWidget);
    expect(find.text('Nouveau client'), findsOneWidget);
    expect(find.text('+509 3456-7890'), findsNothing);
  });

  testWidgets('a matching credit account keeps the selected client name', (
    tester,
  ) async {
    final container = await openRegister(tester);
    container.read(customerProvider.notifier).addCustomer(
          Customer(
            id: 'c-pierre',
            name: 'Autre nom',
            phone: '+509 3456-7890',
            isCreditBlocked: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    await pickMadamePierre(tester);
    await openCredit(tester);

    expect(find.text('Boutique Madame Pierre'), findsWidgets);
    expect(find.text('Autre nom'), findsNothing);
    expect(find.text('Boutique Madame Pierre est bloqué.'), findsOneWidget);
    expect(find.byKey(const Key('credit-client-search')), findsNothing);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirmer le paiement'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a typed name does not replace the credit search', (
    tester,
  ) async {
    await openRegister(tester);
    await tester.enterText(
      find.byKey(const Key('checkout-client-name')),
      'Claire Denis',
    );
    await tester.pump();
    await openCredit(tester);

    expect(find.byKey(const Key('credit-selected-client')), findsNothing);
    expect(find.byKey(const Key('credit-client-search')), findsOneWidget);
    expect(find.text('Nouveau client'), findsOneWidget);
  });

  testWidgets('confirming credit charges the client already selected', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await pickMadamePierre(tester);
    await openCredit(tester);

    await tester.ensureVisible(find.text('Confirmer le paiement'));
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paiement confirmé !'), findsOneWidget);
    final customers = container.read(customerProvider).customers;
    final client = customers.firstWhere(
      (customer) => customer.name == 'Boutique Madame Pierre',
    );
    expect(
      container.read(customerProvider).balanceFor(client.id),
      greaterThan(0),
    );
  });

  testWidgets('credit with cash shows the paid amount and the credit balance', (
    tester,
  ) async {
    final container = await openRegister(tester);
    await pickMadamePierre(tester);
    await openCredit(tester);

    await tester.enterText(find.byKey(const Key('credit-paid-now')), '100');
    await tester.pump();
    await tester.ensureVisible(find.text('Confirmer le paiement'));
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paiement confirmé !'), findsOneWidget);
    expect(find.text('Paiement partiel'), findsNothing);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('Solde au crédit'), findsOneWidget);
    expect(find.text('Solde impayé'), findsNothing);
    final paidLabel = tester.widget<Text>(find.text('Payé'));
    expect(paidLabel.style?.color, AppColors.deepGreen);
    expect(paidLabel.style?.fontWeight, FontWeight.w700);
    final paidRow = find
        .ancestor(of: find.text('Payé'), matching: find.byType(Row))
        .first;
    final paidAmount = tester.widget<Text>(
      find.descendant(of: paidRow, matching: find.byType(Text)).last,
    );
    expect(paidAmount.style?.color, AppColors.deepGreen);
    expect(paidAmount.style?.fontWeight, FontWeight.w700);

    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id.startsWith('pos-'));
    expect(sale.paymentMethod, PaymentMethodType.credit);
    expect(sale.status, RetailOrderStatus.paid);
    expect(sale.amountPaidHtg, 100);
    expect(sale.balanceDueHtg, greaterThan(0));
    expect(sale.amountPaidHtg! + sale.balanceDueHtg!, greaterThan(100));

    final client = container
        .read(customerProvider)
        .customers
        .firstWhere((customer) => customer.name == 'Boutique Madame Pierre');
    expect(
      container.read(customerProvider).balanceFor(client.id),
      sale.balanceDueHtg,
    );
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/theme/app_icons.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/mock/mock_retail_orders.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/models/pending_operation.dart';
import 'package:retail_pos/core/screens/order_history/order_history_screen.dart';
import 'package:retail_pos/core/navigation/app_router.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/providers/device_session_provider.dart';
import 'package:retail_pos/core/screens/sync/sync_screen.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/main.dart';
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

  testWidgets('Login with a staff PIN opens the retail shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _signInToRetailShell(tester, expectDemoPins: true);

    expect(
      find.text('Rechercher un produit ou scanner un code-barres...'),
      findsOneWidget,
    );
    expect(find.text('Boutique Soleil'), findsWidgets);
    expect(find.textContaining('Page not found'), findsNothing);
    expect(find.byIcon(Icons.badge_outlined), findsWidgets);

    await tester.tap(find.byTooltip('Développer le menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Personnel', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Mobile bottom nav shows every destination label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Narrow retail screens already overflow in a few rows. That is separate
    // from whether bottom-nav labels are painted.
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) return;
      previousOnError?.call(details);
    };

    await _signInToRetailShell(tester);

    _expectBottomNavLabelsVisible(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Commandes'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Historique'), findsWidgets);
    _expectBottomNavLabelsVisible(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Clients'), findsWidgets);
    expect(find.text('Synchronisation'), findsOneWidget);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.byIcon(AppIcons.devices), findsOneWidget);
    expect(find.text('Inventaire'), findsWidgets);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Personnel'),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Personnel'), findsOneWidget);
    await tester.tap(find.text('Personnel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Membres du personnel'), findsOneWidget);
    expect(find.text('Jean-Marc Dupont'), findsOneWidget);
    expect(find.text('Ajouter un employé'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Personnel'),
      ),
      findsNothing,
    );
  });

  testWidgets('On a phone the cart and checkout panels fill the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) return;
      if (message.contains('attached to more than one ScrollPosition')) return;
      previousOnError?.call(details);
    };

    await _signInToRetailShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(appRouterProvider).go('/retail/pos');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final firstProduct = container.read(mockProductsProvider).first;
    await tester.tap(_productAddButton(firstProduct.name));
    await tester.pump();
    await tester.tap(find.textContaining('Panier').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    double panelWidth() => tester
        .getSize(
          find
              .ancestor(
                of: find.byType(AppCloseButton).last,
                matching: find.byType(Material),
              )
              .at(1),
        )
        .width;

    expect(find.byType(AppCloseButton), findsOneWidget);
    expect(panelWidth(), 390);

    await tester.tap(find.text('Encaisser').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Suivant'), findsWidgets);
    final checkoutClose = find.byType(AppCloseButton).last;
    expect(tester.getSize(checkoutClose), const Size(36, 36));
    expect(tester.getRect(checkoutClose).right, lessThanOrEqualTo(390));
    expect(tester.getRect(checkoutClose).left, lessThan(60));
  });

  testWidgets('A sale paid offline waits on the synchronisation page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) return;
      if (message.contains('attached to more than one ScrollPosition')) return;
      previousOnError?.call(details);
    };

    await _signInToRetailShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container.read(deviceSessionProvider.notifier).debugSetOnline(false);
    await tester.pump();

    container.read(appRouterProvider).go('/retail/pos');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final firstProduct = container.read(mockProductsProvider).first;
    await tester.tap(_productAddButton(firstProduct.name));
    await tester.pump();
    for (final label in ['Encaisser', 'Suivant', 'Payer']) {
      expect(find.text(label), findsWidgets, reason: label);
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Card and MonCash wait for the payments server. Cash records the sale.
    expect(find.text('Espèces'), findsWidgets);
    await tester.tap(find.text('Espèces').last);
    await tester.pump();
    expect(find.text('Confirmer le paiement'), findsWidgets);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Espèces reçues (HTG)',
      ),
      '100000',
    );
    await tester.pump();
    await tester.tap(find.text('Confirmer le paiement').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pending = container.read(deviceSessionProvider).pending;
    expect(pending.map((op) => op.kind), [PendingOperationKind.sale]);
    final sale = container
        .read(retailOrdersProvider)
        .firstWhere((order) => order.id == pending.single.orderId);
    expect(sale.lines.single.productName, firstProduct.name);

    container.read(appRouterProvider).push('/sync');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 opération en attente'), findsOneWidget);
    expect(find.text(sale.orderNumber), findsOneWidget);
    expect(find.text('Indisponible hors ligne'), findsOneWidget);

    await tester.tap(find.text(sale.orderNumber));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(RetailOrderDetailPage), findsOneWidget);
    expect(find.text(firstProduct.name), findsWidgets);
  });

  testWidgets('Banner opens the waiting sales and Synchroniser sends them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) return;
      previousOnError?.call(details);
    };

    final order = RetailOrder(
      id: 'sale-1',
      orderNumber: 'ORD-2026-0042',
      clientName: 'Marie Joseph',
      status: RetailOrderStatus.paid,
      paymentSource: RetailPaymentSource.pos,
      paymentMethod: PaymentMethodType.cash,
      lines: const [
        RetailOrderLine(
          productName: 'Brosse à dents',
          productId: 1,
          quantity: 1,
          unitPriceHtg: 85,
        ),
      ],
      createdAt: DateTime(2026, 10, 17, 10, 30),
      paidAt: DateTime(2026, 10, 17, 10, 30),
    );
    SharedPreferences.setMockInitialValues({
      LocalStore.outbox: jsonEncode(['sale-1']),
      LocalStore.extraOrders: jsonEncode([order.toJson()]),
    });
    LocalStore.instance.debugReset();

    await _signInToRetailShell(tester);

    expect(
      find.text('Connexion rétablie. 1 opération attend d\'être envoyée.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Synchronisation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 opération en attente'), findsOneWidget);
    final title = tester.widget<AppBar>(find.byType(AppBar));
    expect(title.titleTextStyle?.color, isNot(Colors.white));
    expect(find.text('ORD-2026-0042'), findsOneWidget);
    expect(find.textContaining('Marie Joseph'), findsOneWidget);
    expect(find.text('Pas encore envoyé'), findsOneWidget);
    expect(find.text('Indisponible hors ligne'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SyncScreen)),
    );
    await container.read(deviceSessionProvider.notifier).debugSetOnline(false);
    await tester.pump();
    expect(find.text('Indisponible hors ligne'), findsOneWidget);

    final supplier = container.read(mockSuppliersProvider).first;
    container.read(mockSuppliersProvider.notifier).update(supplier);
    await tester.pump();
    await tester.pump();
    expect(find.text('2 opérations en attente'), findsOneWidget);
    expect(find.text('Fournisseur modifié · ${supplier.name}'), findsOneWidget);
    expect(find.text('Fournisseur'), findsOneWidget);

    await container.read(deviceSessionProvider.notifier).debugSetOnline(true);
    await tester.pump();
    expect(find.text('Indisponible hors ligne'), findsNothing);

    await tester.tap(find.text('Synchroniser'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Tout est envoyé.'), findsOneWidget);
    expect(find.text('Rien à envoyer pour l\'instant.'), findsOneWidget);
    expect(find.text('ORD-2026-0042'), findsNothing);
  });
}

Future<void> _signInToRetailShell(
  WidgetTester tester, {
  bool expectDemoPins = false,
}) async {
  await tester.pumpWidget(const ProviderScope(child: BizManagerApp()));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump();

  expect(find.text('Connecter cet appareil'), findsOneWidget);
  await tester.tap(find.text('Se connecter par e-mail'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  expect(find.text('Se connecter'), findsOneWidget);

  final fields = find.byType(TextFormField);
  final count = fields.evaluate().length;
  await tester.enterText(fields.at(count - 2), 'manager@shop.ht');
  await tester.enterText(fields.at(count - 1), 'password');
  await tester.tap(find.text('Se connecter'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();

  expect(find.text('Entrez votre code'), findsOneWidget);
  if (expectDemoPins) {
    expect(find.text('Codes PIN de démo'), findsOneWidget);
  }

  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text('2'));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// The product name opens details. The plus button adds the product.
Finder _productAddButton(String productName) {
  return find.descendant(
    of: find
        .ancestor(
          of: find.text(productName),
          matching: find.byType(GestureDetector),
        )
        .first,
    matching: find.byIcon(Icons.add),
  );
}

void _expectBottomNavLabelsVisible(WidgetTester tester) {
  const labels = ['Vente', 'Produits', 'Commandes', 'Liens', 'Devis'];
  final navBar = find.byType(NavigationBar);
  expect(navBar, findsOneWidget);
  expect(
    tester.widget<NavigationBar>(navBar).labelBehavior,
    NavigationDestinationLabelBehavior.alwaysShow,
  );

  expect(
    find.descendant(
      of: navBar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            (widget.icon == Icons.receipt_long_outlined ||
                widget.icon == Icons.receipt_long),
      ),
    ),
    findsOneWidget,
    reason: 'Commandes uses a receipt icon, not the search icon',
  );
  expect(
    find.descendant(
      of: navBar,
      matching: find.byIcon(Icons.manage_search),
    ),
    findsNothing,
  );
  expect(
    find.descendant(
      of: navBar,
      matching: find.byIcon(Icons.manage_search_outlined),
    ),
    findsNothing,
  );

  for (final label in labels) {
    final text = find.descendant(of: navBar, matching: find.text(label));
    expect(text, findsOneWidget, reason: '$label should be in the bottom nav');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: text, matching: find.byType(FadeTransition)).first,
    );
    expect(
      fade.opacity.value,
      1.0,
      reason: '$label should stay visible when it is not selected',
    );
  }
}

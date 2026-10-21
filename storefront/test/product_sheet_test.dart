import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/retail/models/sale_measure.dart';
import 'package:retail_storefront/api.dart';
import 'package:retail_storefront/cart.dart';
import 'package:retail_storefront/screens/product_sheet.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the vitrine length field stops at the whole roll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final product = Product(
      id: 'ribbon',
      name: 'Rouleau de ruban adhésif',
      category: 'Quincaillerie',
      description: 'Minimum 6 pouces.',
      priceHtg: 8,
      regularPriceHtg: 8,
      photoUrl: '',
      available: true,
      maxQuantity: 20,
      unit: 'po',
      options: const [],
      saleMode: SaleMode.roll,
      rollPriceHtg: 250,
      minWidth: 6,
      rollWidth: 36,
      trackStock: true,
      stock: 108,
    );
    final shop = Shop(
      slug: 'demo',
      name: 'Demo',
      phone: '',
      address: '',
      description: '',
      pickupNote: '',
      coverUrl: '',
      usdRate: 135,
      availability: const Availability(
        isOpenNow: true,
        paused: false,
        acceptsOrders: true,
        acceptsQuotes: true,
        opensAtLabel: null,
        openHour: 8,
        closeHour: 18,
        closedWeekdays: [],
      ),
      categories: const ['Quincaillerie'],
      products: [product],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showProductSheet(
                context,
                shop: shop,
                product: product,
                cart: Cart(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Entrer une longueur'));
    await tester.pump();
    expect(find.textContaining('maximum 36 po'), findsWidgets);

    await tester.enterText(find.byType(TextField), '450');
    await tester.pump();
    final typed = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(typed == '450', isFalse);
    expect(typed.isEmpty || int.parse(typed) <= 36, isTrue);
    expect(find.textContaining('Ajouter'), findsNothing);

    await tester.enterText(find.byType(TextField), '36');
    await tester.pump();
    expect(find.textContaining('Ajouter'), findsOneWidget);
  });
}

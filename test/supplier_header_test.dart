import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/retail/screens/supplier_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SupplierScreen())),
    );
    await tester.pump();
  }

  testWidgets(
    'on a phone the count sits under the title and the button is short',
    (tester) async {
      await pumpAt(tester, const Size(390, 844));

      expect(find.text('Fournisseurs'), findsOneWidget);
      expect(find.byKey(const Key('supplier-count')), findsOneWidget);
      expect(find.byKey(const Key('supplier-count-chip')), findsNothing);
      expect(find.text('Ajouter un fournisseur'), findsNothing);
      expect(find.text('Fournisseur'), findsOneWidget);

      final title = tester.getTopLeft(find.text('Fournisseurs'));
      final count = tester.getTopLeft(find.byKey(const Key('supplier-count')));
      expect(count.dy, greaterThan(title.dy));
      expect(count.dx, closeTo(title.dx, 1));
    },
  );

  testWidgets('on an iPad the count stays under the title', (tester) async {
    await pumpAt(tester, const Size(834, 1112));

    expect(find.byKey(const Key('supplier-count')), findsOneWidget);
    expect(find.byKey(const Key('supplier-count-chip')), findsNothing);
    expect(find.text('Ajouter un fournisseur'), findsOneWidget);
  });

  testWidgets('on a wide screen the count stays in a tag', (tester) async {
    await pumpAt(tester, const Size(1600, 900));

    expect(find.byKey(const Key('supplier-count-chip')), findsOneWidget);
    expect(find.byKey(const Key('supplier-count')), findsNothing);
    expect(find.text('Ajouter un fournisseur'), findsOneWidget);
  });

  testWidgets(
    'a chosen category clears from a circle at the end of the field',
    (tester) async {
      await pumpAt(tester, const Size(390, 844));

      await tester.tap(find.text('Toutes les catégories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Boissons').last);
      await tester.pumpAndSettle();

      expect(find.text('Toutes les catégories'), findsNothing);
      expect(find.byTooltip('Effacer la catégorie'), findsOneWidget);
      final circle = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.close_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((circle.decoration! as BoxDecoration).shape, BoxShape.circle);

      final label = tester.getCenter(find.text('Boissons').first);
      final close = tester.getCenter(find.byIcon(Icons.close_rounded));
      expect(close.dx, greaterThan(label.dx));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Toutes les catégories'), findsOneWidget);
      expect(find.byTooltip('Effacer la catégorie'), findsNothing);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/retail/screens/retail_inventory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr');
  });

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RetailInventoryScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'inventory category clears from a circle at the end of the field',
    (tester) async {
      await pumpPhone(tester);

      await tester.tap(find.text('Toutes les catégories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ménage').last);
      await tester.pumpAndSettle();

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
      final label = tester.getCenter(find.text('Ménage').first);
      final close = tester.getCenter(find.byIcon(Icons.close_rounded));
      expect(close.dx, greaterThan(label.dx));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Toutes les catégories'), findsOneWidget);
      expect(find.byTooltip('Effacer la catégorie'), findsNothing);
    },
  );

  testWidgets('Annuler matches the height of Appliquer', (tester) async {
    await pumpPhone(tester);

    await tester.tap(find.text('Allumettes (boîte)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajuster le solde'));
    await tester.tap(find.text('Ajuster le solde'));
    await tester.pumpAndSettle();

    final cancel = tester.getSize(
      find.widgetWithText(OutlinedButton, 'Annuler'),
    );
    final apply = tester.getSize(
      find.widgetWithText(ElevatedButton, 'Appliquer'),
    );
    expect(cancel.height, apply.height);
  });
}

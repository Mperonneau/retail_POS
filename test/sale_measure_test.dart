import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/retail/models/sale_measure.dart';
import 'package:retail_pos/retail/widgets/sale_measure_picker.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('a width is the price per inch times the inches', () {
    const cut = MeasureChoice.width(36);
    expect(cut.baseHtg(priceHtg: 15, rollPriceHtg: 750, casePriceHtg: 0), 540);
    expect(cut.unitsEach(rollWidth: 60, unitsPerCase: 0), 36);
    expect(cut.label(unitsPerCase: 0), '36 po');
    expect(cut.rejectReason(mode: SaleMode.roll, minWidth: 12), isNull);
    expect(
      const MeasureChoice.width(
        8,
      ).rejectReason(mode: SaleMode.roll, minWidth: 12),
      isNotNull,
    );
    expect(
      const MeasureChoice.width(
        61,
      ).rejectReason(mode: SaleMode.roll, minWidth: 12, maxWidth: 60),
      'Le maximum est 60 po.',
    );
    expect(
      const MeasureChoice.width(
        60,
      ).rejectReason(mode: SaleMode.roll, minWidth: 12, maxWidth: 60),
      isNull,
    );
    const formatter = MaxInchesFormatter(36);
    expect(
      formatter
          .formatEditUpdate(
            const TextEditingValue(text: '3'),
            const TextEditingValue(text: '36'),
          )
          .text,
      '36',
    );
    expect(
      formatter
          .formatEditUpdate(
            const TextEditingValue(text: '36'),
            const TextEditingValue(text: '360'),
          )
          .text,
      '36',
    );
    expect(
      const MeasureChoice.fullRoll().baseHtg(
        priceHtg: 15,
        rollPriceHtg: 750,
        casePriceHtg: 0,
      ),
      750,
    );
    expect(
      const MeasureChoice.fullRoll().unitsEach(rollWidth: 60, unitsPerCase: 0),
      60,
    );
  });

  test('a case and a single unit keep their own prices', () {
    expect(
      const MeasureChoice.casePack().baseHtg(
        priceHtg: 40,
        rollPriceHtg: 0,
        casePriceHtg: 800,
      ),
      800,
    );
    expect(
      const MeasureChoice.casePack().unitsEach(rollWidth: 0, unitsPerCase: 24),
      24,
    );
    expect(
      const MeasureChoice.casePack().label(unitsPerCase: 24),
      'Caisse de 24',
    );
    expect(
      const MeasureChoice.each().baseHtg(
        priceHtg: 40,
        rollPriceHtg: 0,
        casePriceHtg: 800,
      ),
      40,
    );
    expect(
      const MeasureChoice.each().unitsEach(rollWidth: 0, unitsPerCase: 24),
      1,
    );
    expect(measureFromLabel('36 po').width, 36);
    expect(
      measureForMode(SaleMode.roll, 'Longueur entière').kind,
      MeasureKind.fullRoll,
    );
    expect(
      measureForMode(SaleMode.roll, 'Rouleau entier').kind,
      MeasureKind.fullRoll,
    );
    expect(measureForMode(SaleMode.piece, '36 po').kind, MeasureKind.plain);
  });

  testWidgets(
    'the register length field stops at the whole roll when limited',
    (tester) async {
      final product = MockProduct(
        id: 37,
        name: 'Rouleau de ruban adhésif',
        category: 'Quincaillerie',
        priceHtg: 8,
        priceUsd: 0.08,
        costHtg: 4,
        stockQuantity: 108,
        minStock: 36,
        saleMode: SaleMode.roll,
        rollPriceHtg: 250,
        rollPriceUsd: 2.50,
        minWidth: 6,
        rollWidth: 36,
        limitLength: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showSaleMeasurePicker(
                    context,
                    product,
                    roomFor: (_, __) => 10,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrer une longueur'));
      await tester.pumpAndSettle();
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
    },
  );

  testWidgets('the register accepts a length past the roll unless limited', (
    tester,
  ) async {
    final product = MockProduct(
      id: 37,
      name: 'Rouleau de ruban adhésif',
      category: 'Quincaillerie',
      priceHtg: 8,
      priceUsd: 0.08,
      costHtg: 4,
      stockQuantity: 500,
      minStock: 36,
      saleMode: SaleMode.roll,
      rollPriceHtg: 250,
      rollPriceUsd: 2.50,
      minWidth: 6,
      rollWidth: 36,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSaleMeasurePicker(
                  context,
                  product,
                  roomFor: (_, __) => 10,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrer une longueur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('maximum 36 po'), findsNothing);

    await tester.enterText(find.byType(TextField), '450');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '450',
    );
    expect(find.textContaining('Ajouter'), findsOneWidget);
  });
}

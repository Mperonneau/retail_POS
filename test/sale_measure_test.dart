import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/retail/models/sale_measure.dart';

void main() {
  test('a width is the price per inch times the inches', () {
    const cut = MeasureChoice.width(36);
    expect(
      cut.baseHtg(priceHtg: 15, rollPriceHtg: 750, casePriceHtg: 0),
      540,
    );
    expect(cut.unitsEach(rollWidth: 60, unitsPerCase: 0), 36);
    expect(cut.label(unitsPerCase: 0), '36 po');
    expect(cut.rejectReason(mode: SaleMode.roll, minWidth: 12), isNull);
    expect(
      const MeasureChoice.width(8).rejectReason(mode: SaleMode.roll, minWidth: 12),
      isNotNull,
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
    expect(const MeasureChoice.each().unitsEach(rollWidth: 0, unitsPerCase: 24), 1);
    expect(measureFromLabel('36 po').width, 36);
    expect(
      measureForMode(SaleMode.roll, 'Rouleau entier').kind,
      MeasureKind.fullRoll,
    );
    expect(measureForMode(SaleMode.piece, '36 po').kind, MeasureKind.plain);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/widgets/phone_field.dart';

void main() {
  test('a bare Haitian number keeps Haiti and the national digits', () {
    final parts = splitPhone('3700 1111');
    expect(parts.country.iso, 'HT');
    expect(parts.national, '37001111');
    expect(formatPhone(parts.country, parts.national), '+509 37001111');
  });

  test('a full number selects the country from the calling code', () {
    expect(splitPhone('+509 3700 1111').country.iso, 'HT');
    expect(splitPhone('50937001111').national, '37001111');
    final france = splitPhone('+33 6 12 34 56 78');
    expect(france.country.iso, 'FR');
    expect(france.national, '612345678');
    expect(splitPhone('+1 809 555 1234').country.iso, 'DO');
    expect(splitPhone('+1 202 555 1234').country.iso, 'US');
  });

  test('an empty number stays on Haiti', () {
    final parts = splitPhone('   ');
    expect(parts.country.iso, 'HT');
    expect(parts.national, '');
    expect(formatPhone(parts.country, parts.national), '');
  });

  testWidgets('the field shows the flag and calling code on the same row', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneField(controller: controller, label: 'Téléphone'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Téléphone'), findsOneWidget);
    expect(find.text('+509'), findsOneWidget);
    expect(find.text(dialCountry('HT').flag), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '37001111');
    await tester.pump();
    expect(controller.text, '+509 37001111');
  });

  testWidgets('a stored French number keeps its flag and calling code', (
    tester,
  ) async {
    final controller = TextEditingController(text: '+33 612345678');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhoneField(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('+33'), findsOneWidget);
    expect(find.text(dialCountry('FR').flag), findsOneWidget);
    expect(find.text('612345678'), findsOneWidget);
    expect(controller.text, '+33 612345678');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/widgets/focus_expand_search_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRow(
    WidgetTester tester, {
    required Size size,
    bool onlyWhenNarrow = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusExpandSearchRow(
            onlyWhenNarrow: onlyWhenNarrow,
            search: const TextField(key: Key('search')),
            trailing: const [Text('Catégories')],
          ),
        ),
      ),
    );
  }

  testWidgets('a narrow search field grows to the row while it is focused', (
    tester,
  ) async {
    await pumpRow(tester, size: const Size(390, 200));

    final search = find.byKey(const Key('search'));
    final before = tester.getSize(search).width;
    expect(find.text('Catégories'), findsOneWidget);
    expect(before, lessThan(320));

    await tester.tap(search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(search).width, greaterThan(before + 40));
    expect(tester.getSize(search).width, greaterThan(370));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.getSize(search).width, closeTo(before, 1));
    expect(find.text('Catégories'), findsOneWidget);
  });

  testWidgets('a wide search row keeps the controls beside the field', (
    tester,
  ) async {
    await pumpRow(tester, size: const Size(900, 200));

    final search = find.byKey(const Key('search'));
    final before = tester.getSize(search).width;

    await tester.tap(search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(search).width, closeTo(before, 1));
    expect(find.text('Catégories'), findsOneWidget);
  });
}

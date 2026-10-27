import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/screens/order_history/order_history_detail.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the receipt page closes beside the number, without a blue bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final record = OrderHistoryRecord(
      receiptNumber: 'RCP-2026-008',
      paidAt: DateTime(2026, 3, 5, 10, 5),
      receiptName: 'Supermarché Caraïbe',
      source: 'Caisse',
      items: [
        OrderHistoryItem(name: 'Savon Palmolive', quantity: 1, priceHtg: 1440),
      ],
      taxPercent: 10,
      paymentMethod: PaymentMethodType.cash,
      module: OrderHistoryModule.retail,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderHistoryDetailPage(record: record),
                    ),
                  );
                },
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('RCP-2026-008'), findsOneWidget);
    expect(find.byType(AppCloseButton), findsOneWidget);

    final close = tester.getTopLeft(find.byType(AppCloseButton));
    final number = tester.getTopLeft(find.text('RCP-2026-008'));
    expect(close.dx, lessThan(number.dx));
    expect((close.dy - number.dy).abs(), lessThan(28));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('RCP-2026-008'), findsNothing);
    expect(find.text('Ouvrir'), findsOneWidget);
  });
}

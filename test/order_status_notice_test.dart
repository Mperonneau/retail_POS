import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/mock/mock_retail_orders.dart';
import 'package:retail_pos/core/models/order_history.dart';
import 'package:retail_pos/core/models/retail_fulfillment_mode.dart';
import 'package:retail_pos/core/models/retail_order.dart';
import 'package:retail_pos/core/screens/order_history/order_history_screen.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
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

  test('status notices name the new state', () {
    expect(
      orderStatusNoticeMessage('QTE-2026-0007', RetailOrderStatus.completed),
      'Commande QTE-2026-0007 marquée comme terminée',
    );
    expect(
      orderStatusNoticeMessage('QTE-2026-0007', RetailOrderStatus.delivered),
      'Commande QTE-2026-0007 marquée comme livrée',
    );
    expect(
      orderStatusNoticeMessage('QTE-2026-0007', RetailOrderStatus.ready),
      'Commande QTE-2026-0007 marquée comme prête',
    );
    expect(
      orderStatusNoticeMessage('QTE-2026-0007', RetailOrderStatus.pickedUp),
      'Commande QTE-2026-0007 marquée comme retirée',
    );
  });

  testWidgets('marking an order shows a confirmation at the top', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final order = RetailOrder(
      id: 'pos-notice',
      orderNumber: 'QTE-2026-0007',
      clientName: 'Philippe Moreau',
      status: RetailOrderStatus.ready,
      paymentSource: RetailPaymentSource.paymentLink,
      paymentMethod: PaymentMethodType.moncash,
      fulfillmentMode: RetailFulfillmentMode.delivery,
      lines: const [
        RetailOrderLine(
          productName: 'Eau Culligan 18L',
          productId: 1,
          quantity: 5,
          unitPriceHtg: 280,
        ),
      ],
      createdAt: DateTime(2026, 10, 27, 11),
      paidAt: DateTime(2026, 10, 27, 11),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(retailOrdersProvider.notifier).add(order);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: RetailOrderDetailPage(order: order),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Marquer livré'));
    await tester.tap(find.text('Marquer livré'));
    await tester.pump();

    expect(
      find.text('Commande QTE-2026-0007 marquée comme livrée'),
      findsOneWidget,
    );
    final noticeTop = tester.getTopLeft(find.byKey(const Key('order-status-notice'))).dy;
    final buttonTop = tester.getTopLeft(find.text('Marquer terminé')).dy;
    expect(noticeTop, lessThan(80));
    expect(noticeTop, lessThan(buttonTop));

    final updated = container
        .read(retailOrdersProvider)
        .firstWhere((row) => row.id == order.id);
    expect(updated.status, RetailOrderStatus.delivered);

    await tester.ensureVisible(find.text('Marquer terminé'));
    await tester.tap(find.text('Marquer terminé'));
    await tester.pump();

    expect(
      find.text('Commande QTE-2026-0007 marquée comme terminée'),
      findsOneWidget,
    );
    expect(
      find.text('Commande QTE-2026-0007 marquée comme livrée'),
      findsNothing,
    );
    expect(
      container
          .read(retailOrdersProvider)
          .firstWhere((row) => row.id == order.id)
          .status,
      RetailOrderStatus.completed,
    );
    expect(find.text('Marquer terminé'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
  });
}

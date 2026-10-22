import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/models/customer.dart';
import 'package:retail_pos/core/screens/customers/customer_payment_modal.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/core/widgets/payment_receipt_dialogs.dart';
import 'package:retail_pos/retail/receipt/share_receipt_file.dart';
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

  testWidgets('the WhatsApp window stays as tall as the phone field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => PaymentReceiptDialogs.showWhatsApp(context),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer par WhatsApp'), findsOneWidget);
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Envoyer'), findsOneWidget);

    final field = tester.getRect(find.text('Numéro de téléphone'));
    final cancel = tester.getRect(find.text('Annuler'));
    final window = tester.getRect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Material),
      ).first,
    );
    expect(cancel.top - field.bottom, lessThan(160));
    expect(window.height, lessThan(420));
    expect(window.height, lessThan(tester.view.physicalSize.height * 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an account receipt can be shared from the phone', (
    tester,
  ) async {
    final shared = <({Uint8List bytes, String filename, String subject})>[];
    final previous = shareReceiptFile;
    shareReceiptFile =
        ({
          required Uint8List bytes,
          required String filename,
          required String subject,
        }) async {
          shared.add((bytes: bytes, filename: filename, subject: subject));
        };
    addTearDown(() => shareReceiptFile = previous);

    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final customer = Customer(
      id: 'jean-pierre',
      name: 'Jean-Pierre Étienne',
      phone: '+509 3456-1234',
      createdAt: DateTime(2026, 10, 22),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showCustomerAccountPayment(
                    context,
                    customer: customer,
                    balance: 2400,
                    isDark: false,
                  );
                },
                child: const Text('Payer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Payer'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final paymentPanel = tester.getRect(
      find
          .ancestor(
            of: find.text('Paiement de compte'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(paymentPanel.right, 800);
    expect(paymentPanel.width, 480);

    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    await tester.ensureVisible(find.text('Confirmer le paiement'));
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pumpAndSettle();

    expect(find.text('Paiement de compte'), findsNothing);
    expect(find.text('Paiement confirmé'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    final receiptPanel = tester.getRect(
      find
          .ancestor(
            of: find.text('Paiement confirmé'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(receiptPanel.right, 800);
    expect(receiptPanel.width, 480);

    final share = tester.getSize(find.byKey(const Key('account-receipt-share')));
    expect(share.width, greaterThan(200));

    await tester.ensureVisible(find.byKey(const Key('account-receipt-share')));
    await tester.tap(find.byKey(const Key('account-receipt-share')));
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    expect(String.fromCharCodes(shared.single.bytes.take(5)), '%PDF-');
    expect(shared.single.filename, startsWith('recu-PAY-'));
    expect(shared.single.filename, endsWith('.pdf'));
    expect(shared.single.subject, startsWith('Reçu PAY-'));
    expect(find.text('Le document n\'a pas pu être préparé.'), findsNothing);
  });

  testWidgets('account payment fills the phone screen from the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final customer = Customer(
      id: 'marie',
      name: 'Marie-Josée Beaumont',
      phone: '+509 3789-5678',
      createdAt: DateTime(2026, 10, 22),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showCustomerAccountPayment(
                    context,
                    customer: customer,
                    balance: 4668,
                    isDark: false,
                  );
                },
                child: const Text('Payer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Payer'));
    await tester.pumpAndSettle();

    expect(find.text('Paiement de compte'), findsOneWidget);
    expect(find.text('MonCash'), findsOneWidget);
    expect(find.text('Carte'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    final panel = tester.getRect(
      find
          .ancestor(
            of: find.text('Paiement de compte'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panel.left, 0);
    expect(panel.width, 390);
    expect(tester.takeException(), isNull);
  });
}

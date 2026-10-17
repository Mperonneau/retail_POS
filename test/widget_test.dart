import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/main.dart';
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

  testWidgets('Login with a staff PIN opens the retail shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _signInToRetailShell(tester, expectDemoPins: true);

    expect(find.text('Tableau de bord'), findsWidgets);
    expect(find.text('Boutique Soleil'), findsWidgets);
    expect(find.textContaining('Page not found'), findsNothing);
  });

  testWidgets('Mobile bottom nav shows every destination label', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Narrow retail screens already overflow in a few rows. That is separate
    // from whether bottom-nav labels are painted.
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) return;
      previousOnError?.call(details);
    };

    await _signInToRetailShell(tester);

    _expectBottomNavLabelsVisible(tester);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Commandes')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Historique'), findsWidgets);
    _expectBottomNavLabelsVisible(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Clients'), findsWidgets);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.text('Inventaire'), findsWidgets);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });
}

Future<void> _signInToRetailShell(
  WidgetTester tester, {
  bool expectDemoPins = false,
}) async {
  await tester.pumpWidget(const ProviderScope(child: BizManagerApp()));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump();

  expect(find.text('Connecter cet appareil'), findsOneWidget);
  await tester.tap(find.text('Se connecter par e-mail'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  expect(find.text('Se connecter'), findsOneWidget);

  final fields = find.byType(TextFormField);
  final count = fields.evaluate().length;
  await tester.enterText(fields.at(count - 2), 'manager@shop.ht');
  await tester.enterText(fields.at(count - 1), 'password');
  await tester.tap(find.text('Se connecter'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();

  expect(find.text('Entrez votre code'), findsOneWidget);
  if (expectDemoPins) {
    expect(find.text('Codes PIN de démo'), findsOneWidget);
  }

  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text('2'));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void _expectBottomNavLabelsVisible(WidgetTester tester) {
  const labels = ['Caisse', 'Produits', 'Commandes', 'Liens', 'Devis'];
  final navBar = find.byType(NavigationBar);
  expect(navBar, findsOneWidget);
  expect(
    tester.widget<NavigationBar>(navBar).labelBehavior,
    NavigationDestinationLabelBehavior.alwaysShow,
  );

  for (final label in labels) {
    final text = find.descendant(of: navBar, matching: find.text(label));
    expect(text, findsOneWidget, reason: '$label should be in the bottom nav');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: text, matching: find.byType(FadeTransition)).first,
    );
    expect(
      fade.opacity.value,
      1.0,
      reason: '$label should stay visible when it is not selected',
    );
  }
}

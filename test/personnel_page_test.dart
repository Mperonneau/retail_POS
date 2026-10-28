import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/settings/screens/settings_screen.dart';
import 'package:retail_pos/settings/screens/staff_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Personnel lists the staff on its own page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: StaffScreen())),
    );

    expect(find.text('Personnel'), findsOneWidget);
    expect(find.text('Membres du personnel'), findsOneWidget);
    expect(find.text('un employé'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    final addButton = tester.getSize(find.widgetWithText(AppButton, 'un employé'));
    expect(addButton.width, 160);
    expect(addButton.height, 40);
    expect(find.text('Actifs'), findsOneWidget);
    expect(find.text('Inactifs'), findsOneWidget);
    expect(find.text('Jean-Marc Dupont'), findsOneWidget);
    expect(find.text('Marie-Carmel Joseph'), findsOneWidget);
    expect(find.text('Marcel Toussaint'), findsNothing);

    await tester.tap(find.text('Inactifs'));
    await tester.pumpAndSettle();

    expect(find.text('Marcel Toussaint'), findsOneWidget);
    expect(find.text('Jean-Marc Dupont'), findsNothing);
    expect(find.text('Marie-Carmel Joseph'), findsNothing);
  });

  testWidgets('Deactivating an employee moves them to Inactifs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: StaffScreen())),
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Jean-Marc Dupont'), findsNothing);

    await tester.tap(find.text('Inactifs'));
    await tester.pumpAndSettle();

    expect(find.text('Jean-Marc Dupont'), findsOneWidget);
    expect(find.text('Marcel Toussaint'), findsOneWidget);
  });

  testWidgets('Paramètres no longer includes a Personnel tab', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Personnel'),
      ),
      findsNothing,
    );
    expect(find.text('Commerce', skipOffstage: false), findsOneWidget);
    expect(find.text('Permissions', skipOffstage: false), findsOneWidget);
    expect(find.text('Abonnement', skipOffstage: false), findsOneWidget);
    expect(find.text('Personnel', skipOffstage: false), findsNothing);
  });
}

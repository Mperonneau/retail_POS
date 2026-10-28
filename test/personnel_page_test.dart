import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
    expect(find.text('Ajouter un employé'), findsOneWidget);
    expect(find.text('Jean-Marc Dupont'), findsOneWidget);
    expect(find.text('Marie-Carmel Joseph'), findsOneWidget);
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

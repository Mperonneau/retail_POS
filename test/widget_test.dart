import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Login with a staff PIN opens the retail shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: BizManagerApp()));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'manager@shop.ht');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(find.text('Demo PINs'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('2'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Retail Dashboard'), findsOneWidget);
    expect(find.text('Boutique Soleil'), findsWidgets);
    expect(find.textContaining('Page not found'), findsNothing);
  });
}

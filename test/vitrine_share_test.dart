import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/theme/app_theme.dart';
import 'package:retail_pos/retail/screens/vitrine_screen.dart';
import 'package:retail_pos/retail/storefront/share_vitrine.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'retail.storefront.settings': jsonEncode({
        'enabled': false,
        'paused': false,
        'slug': 'boutique-soleil',
        'displayName': 'Morel Multi Services',
        'description': 'a big magasin',
        'city': 'Jacmel',
        'department': 'Sud-Est',
        'categories': [
          'Boulangerie',
          'Glace et surgelés',
          'Horlogerie',
          'Linge de maison',
        ],
        'openHour': 8,
        'closeHour': 18,
        'coverDataUrl': 'data:image/png;base64,$_png',
        'everPublished': true,
      }),
    });
    LocalStore.instance.debugReset();
  });

  test('the caption carries the shop name, place, and link', () {
    final text = vitrineShareText(
      name: 'Morel Multi Services',
      city: 'Jacmel',
      department: 'Sud-Est',
      categories: const ['Boulangerie', 'Horlogerie'],
      description: 'a big magasin',
      openHour: 8,
      closeHour: 18,
      url: 'https://retail-pos-storefront.onrender.com/boutique-soleil',
    );
    expect(
      text,
      'Morel Multi Services\n'
      'Jacmel, Sud-Est\n'
      'Boulangerie · Horlogerie\n'
      'a big magasin\n'
      'Ouvert 8h – 18h\n'
      'https://retail-pos-storefront.onrender.com/boutique-soleil',
    );
    expect(
      vitrineCoverFile('data:image/png;base64,$_png')?.mime,
      'image/png',
    );
  });

  testWidgets('Partager sits under Aperçu and sends the picture', (
    tester,
  ) async {
    final shared = <VitrineShare>[];
    final previous = shareVitrineCard;
    shareVitrineCard = (share) async => shared.add(share);
    addTearDown(() => shareVitrineCard = previous);

    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light, home: VitrineScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Aperçu de la vitrine'), findsWidgets);
    final preview = find.text('Aperçu de la vitrine').first;
    final share = find.byKey(const Key('vitrine-share'));
    expect(share, findsOneWidget);
    expect(tester.getTopLeft(share).dy, greaterThan(tester.getBottomLeft(preview).dy));

    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pump();

    expect(shared, hasLength(1));
    expect(shared.single.subject, 'Morel Multi Services');
    expect(shared.single.text, contains('Jacmel, Sud-Est'));
    expect(shared.single.text, contains('a big magasin'));
    expect(
      shared.single.text,
      contains('https://retail-pos-storefront.onrender.com/boutique-soleil'),
    );
    expect(shared.single.mime, 'image/png');
    expect(shared.single.image, base64Decode(_png));
  });
}

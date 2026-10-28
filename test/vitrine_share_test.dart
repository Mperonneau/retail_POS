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

  test('the message invites people to order through the link', () {
    final message = vitrineShareMessage('Morel Multi Services');
    expect(
      message,
      'Morel Multi Services est sur Tabkreyol ! '
      'Cliquez sur le lien pour commander chez nous, où que vous soyez.',
    );
    expect(
      vitrineShareText(message, 'https://x.test/boutique-soleil'),
      '$message\nhttps://x.test/boutique-soleil',
    );
    final link = vitrineShareLink('https://x.test/boutique-soleil', ['a', 1]);
    expect(link, startsWith('https://x.test/boutique-soleil?v='));
    expect(vitrineShareLink('https://x.test/boutique-soleil', ['a', 1]), link);
    expect(
      vitrineShareLink('https://x.test/boutique-soleil', ['b', 1]),
      isNot(link),
    );
  });

  testWidgets('Partager sits under Aperçu and sends the shop link', (
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
    expect(
      shared.single.message,
      startsWith('Morel Multi Services est sur Tabkreyol !'),
    );
    expect(
      shared.single.url,
      startsWith('https://retail-pos-vitrine.onrender.com/boutique-soleil?v='),
    );
    expect(shared.single.text, contains(shared.single.url!));
  });
}

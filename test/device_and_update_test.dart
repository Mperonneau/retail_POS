import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/mock/mock_retail_data.dart';
import 'package:retail_pos/core/models/pending_operation.dart';
import 'package:retail_pos/core/models/staff_role.dart';
import 'package:retail_pos/core/providers/device_session_provider.dart';
import 'package:retail_pos/core/services/app_update.dart';
import 'package:retail_pos/core/services/device_pairing.dart';
import 'package:retail_pos/core/services/local_store.dart';
import 'package:retail_pos/core/services/pin_shift_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('device code ignores spaces and ambiguous letters', () {
    expect(normalizeDeviceCode(' abcd 12oi '), 'ABCD-1201');
    expect(isCompleteDeviceCode(normalizeDeviceCode('7KQ2M9XD')), isTrue);
    expect(isCompleteDeviceCode('7KQ2'), isFalse);
  });

  test('offline PIN window lasts 14 days', () {
    final verified = DateTime(2026, 10, 1);
    final pairing = DevicePairingInfo(
      token: 't',
      locationName: 'Boutique Soleil',
      pairedAt: verified,
      verifiedAt: verified,
    );
    expect(pairing.offlineExpired(verified.add(const Duration(days: 13))), isFalse);
    expect(pairing.offlineExpired(verified.add(const Duration(days: 14))), isTrue);
    expect(pairing.offlineExpiringSoon(verified.add(const Duration(days: 11))), isTrue);
  });

  test('saved PIN matches locally and a different PIN does not', () {
    final cache = PinShiftCache();
    cache.remember(
      deviceId: 'dev-1',
      pin: '2222',
      userId: 'emp_2222_demo',
      name: 'Marie Joseph',
      role: StaffRole.manager,
    );
    expect(cache.match('dev-1', '2222')?.name, 'Marie Joseph');
    expect(cache.match('dev-1', '1111'), isNull);
    expect(cache.match('other', '2222'), isNull);
    final restored = PinShiftCache.fromJsonList(cache.toJson());
    expect(restored.match('dev-1', '2222')?.role, StaffRole.manager);
  });

  test('changes made offline stay queued until Synchroniser', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      LocalStore.deviceId: 'dev-test',
      LocalStore.outbox: '["sale-1"]',
    });
    LocalStore.instance.debugReset();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.restore();

    List<PendingOperation> pending() => container.read(deviceSessionProvider).pending;
    expect(pending().single.kind, PendingOperationKind.sale);
    expect(pending().single.orderId, 'sale-1');

    final product = container.read(mockProductsProvider).first;
    container.read(mockProductsProvider.notifier).update(product);
    await Future<void>.delayed(Duration.zero);
    expect(pending(), hasLength(1), reason: 'online edits are not queued');

    await notifier.debugSetOnline(false);
    container.read(mockProductsProvider.notifier).update(product);
    container.read(mockSuppliersProvider.notifier).add(
          container.read(mockSuppliersProvider).first,
        );
    container.read(retailInventoryLedgerProvider.notifier).adjust(
          productId: product.id,
          signedDelta: -2,
        );
    await Future<void>.delayed(Duration.zero);
    expect(pending().map((op) => op.kind), [
      PendingOperationKind.stock,
      PendingOperationKind.supplier,
      PendingOperationKind.product,
      PendingOperationKind.sale,
    ]);
    expect(pending().first.title, 'Ajustement de stock · ${product.name}');
    expect(await notifier.syncNow(), isFalse);

    await notifier.debugSetOnline(true);
    expect(pending(), hasLength(4));
    expect(await notifier.syncNow(), isTrue);
    expect(pending(), isEmpty);
    expect(container.read(deviceSessionProvider).lastSyncAt, isNotNull);
    expect(await LocalStore.instance.loadPendingOperations(), isEmpty);
    expect(await LocalStore.instance.loadOutbox(), isEmpty);
  });

  test('a new web build asks to reload and an old build can be forced', () {
    expect(
      evaluateAppUpdate(
        buildNumber: 1,
        buildId: 'abc',
        webManifest: {'build_id': 'abc', 'build_number': 1},
      ).mode,
      AppUpdateMode.none,
    );
    expect(
      evaluateAppUpdate(
        buildNumber: 1,
        buildId: 'abc',
        webManifest: {'build_id': 'def', 'build_number': 1},
      ).mode,
      AppUpdateMode.soft,
    );
    expect(
      evaluateAppUpdate(
        buildNumber: 1,
        buildId: 'abc',
        webManifest: {'build_id': 'def', 'build_number': 4, 'min_build': 3},
      ).mode,
      AppUpdateMode.forced,
    );
    expect(
      evaluateAppUpdate(buildNumber: 1, buildId: 'abc', webManifest: null).mode,
      AppUpdateMode.none,
    );
  });

  test('without a build id, a new main.dart.js ETag asks to reload', () async {
    SharedPreferences.setMockInitialValues({});
    String? etag = 'W/"a"';
    final checker = AppUpdateChecker(
      buildId: '',
      web: true,
      fetch: (_) async => {'version': '1.0.0', 'build_number': '1'},
      fingerprint: (uri) async {
        expect(uri.path, '/main.dart.js');
        return etag;
      },
    );
    await checker.check();
    expect(checker.visible.mode, AppUpdateMode.none);

    etag = null;
    await checker.check();
    expect(checker.visible.mode, AppUpdateMode.none);

    etag = 'W/"b"';
    await checker.check();
    expect(checker.visible.mode, AppUpdateMode.soft);

    await checker.dismiss();
    expect(checker.visible.mode, AppUpdateMode.none);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/models/staff_role.dart';
import 'package:retail_pos/core/services/app_update.dart';
import 'package:retail_pos/core/services/device_pairing.dart';
import 'package:retail_pos/core/services/pin_shift_cache.dart';

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
}

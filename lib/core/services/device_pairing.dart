import 'dart:math';

/// This register is paired to the store. The token stays on the device.
class DevicePairingInfo {
  DevicePairingInfo({
    required this.token,
    required this.locationName,
    required this.pairedAt,
    required this.verifiedAt,
    this.offlineWindowDays = defaultOfflineWindowDays,
  });

  final String token;
  final String locationName;
  final DateTime pairedAt;
  final DateTime verifiedAt;
  final int offlineWindowDays;

  static const defaultOfflineWindowDays = 14;
  static const warningDays = 4;

  int daysLeft(DateTime now) {
    final used = now.difference(verifiedAt).inHours / 24;
    final left = (offlineWindowDays - used).ceil();
    return left < 0 ? 0 : left;
  }

  bool offlineExpired(DateTime now) =>
      now.difference(verifiedAt) >= Duration(days: offlineWindowDays);

  bool offlineExpiringSoon(DateTime now) =>
      !offlineExpired(now) && daysLeft(now) <= warningDays;

  DevicePairingInfo copyWith({DateTime? verifiedAt}) => DevicePairingInfo(
        token: token,
        locationName: locationName,
        pairedAt: pairedAt,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        offlineWindowDays: offlineWindowDays,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'location_name': locationName,
        'paired_at': pairedAt.toIso8601String(),
        'verified_at': verifiedAt.toIso8601String(),
        'offline_window_days': offlineWindowDays,
      };

  static DevicePairingInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) return null;
    final now = DateTime.now();
    return DevicePairingInfo(
      token: token,
      locationName: json['location_name']?.toString() ?? 'Boutique Soleil',
      pairedAt: DateTime.tryParse('${json['paired_at']}') ?? now,
      verifiedAt: DateTime.tryParse('${json['verified_at']}') ?? now,
      offlineWindowDays: (json['offline_window_days'] as num?)?.toInt() ??
          defaultOfflineWindowDays,
    );
  }
}

class DeviceInvite {
  DeviceInvite({
    required this.code,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
    this.deviceName = '',
  });

  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool used;
  final String deviceName;

  bool isLive(DateTime now) => !used && expiresAt.isAfter(now);

  DeviceInvite copyWith({bool? used}) => DeviceInvite(
        code: code,
        createdAt: createdAt,
        expiresAt: expiresAt,
        used: used ?? this.used,
        deviceName: deviceName,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'used': used,
        'device_name': deviceName,
      };

  static DeviceInvite? fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    if (code.isEmpty) return null;
    final now = DateTime.now();
    return DeviceInvite(
      code: code,
      createdAt: DateTime.tryParse('${json['created_at']}') ?? now,
      expiresAt: DateTime.tryParse('${json['expires_at']}') ?? now,
      used: json['used'] == true,
      deviceName: json['device_name']?.toString() ?? '',
    );
  }
}

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';

String generateDeviceCode([Random? random]) {
  final rng = random ?? Random.secure();
  final chars = List.generate(8, (_) => _alphabet[rng.nextInt(_alphabet.length)]);
  return '${chars.take(4).join()}-${chars.skip(4).join()}';
}

/// « abcd 1234 » → « ABCD-1234 ». O / I / L become 0 / 1 / 1.
String normalizeDeviceCode(String raw) {
  final buffer = StringBuffer();
  for (final ch in raw.toUpperCase().split('')) {
    final mapped = switch (ch) { 'O' => '0', 'I' || 'L' => '1', _ => ch };
    if (RegExp(r'[0-9A-Z]').hasMatch(mapped)) buffer.write(mapped);
  }
  final compact = buffer.toString();
  final body = compact.length > 8 ? compact.substring(0, 8) : compact;
  if (body.length <= 4) return body;
  return '${body.substring(0, 4)}-${body.substring(4)}';
}

bool isCompleteDeviceCode(String formatted) =>
    formatted.replaceAll('-', '').length == 8;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/staff_role.dart';

/// A staff PIN remembered on this register.
///
/// The PIN itself is never stored. Only an HMAC and the session facts
/// needed to unlock without calling the server again.
class PinShiftEntry {
  PinShiftEntry({
    required this.userId,
    required this.name,
    required this.role,
    required this.verifier,
    required this.deviceId,
  });

  final String userId;
  final String name;
  final StaffRole role;
  final String verifier;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
        'role': role.name,
        'verifier': verifier,
        'device_id': deviceId,
      };

  static PinShiftEntry? fromJson(Map<String, dynamic> json) {
    final userId = json['user_id']?.toString() ?? '';
    final verifier = json['verifier']?.toString() ?? '';
    if (userId.isEmpty || verifier.isEmpty) return null;
    final roleName = json['role']?.toString() ?? '';
    final role = StaffRole.values.where((r) => r.name == roleName).firstOrNull;
    if (role == null) return null;
    return PinShiftEntry(
      userId: userId,
      name: json['name']?.toString() ?? '',
      role: role,
      verifier: verifier,
      deviceId: json['device_id']?.toString() ?? '',
    );
  }
}

class PinShiftCache {
  PinShiftCache({List<PinShiftEntry>? entries}) : entries = [...?entries];

  final List<PinShiftEntry> entries;

  static String verifierFor(String deviceId, String pin) {
    final key = utf8.encode('retail-pos:$deviceId');
    return Hmac(sha256, key).convert(utf8.encode(pin)).toString();
  }

  PinShiftEntry? match(String deviceId, String pin) {
    final expected = verifierFor(deviceId, pin);
    for (final entry in entries) {
      if (entry.deviceId == deviceId && entry.verifier == expected) {
        return entry;
      }
    }
    return null;
  }

  void remember({
    required String deviceId,
    required String pin,
    required String userId,
    required String name,
    required StaffRole role,
  }) {
    final verifier = verifierFor(deviceId, pin);
    entries.removeWhere((e) => e.deviceId == deviceId && e.userId == userId);
    entries.add(PinShiftEntry(
      userId: userId,
      name: name,
      role: role,
      verifier: verifier,
      deviceId: deviceId,
    ));
  }

  List<Map<String, dynamic>> toJson() =>
      [for (final entry in entries) entry.toJson()];

  static PinShiftCache fromJsonList(List<dynamic>? raw) {
    if (raw == null) return PinShiftCache();
    return PinShiftCache(
      entries: [
        for (final item in raw)
          if (item is Map) PinShiftEntry.fromJson(item.cast<String, dynamic>()),
      ].whereType<PinShiftEntry>().toList(),
    );
  }
}

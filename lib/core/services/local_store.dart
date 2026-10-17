import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_operation.dart';
import '../models/retail_order.dart';

/// Browser / device storage for pairing, PIN cache, and sales made offline.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  static const pairing = 'retail.device_pairing';
  static const profile = 'retail.device_profile';
  static const invites = 'retail.device_invites';
  static const pinCache = 'retail.pin_shift_cache';
  static const deviceId = 'retail.device_id';
  static const extraOrders = 'retail.extra_orders';
  /// Sale ids queued before the queue held every kind of change.
  static const outbox = 'retail.outbox_ids';
  static const pendingOperations = 'retail.pending_operations';
  static const lastSync = 'retail.last_sync_at';
  static const updateDismissed = 'retail.app_update.dismissed';

  SharedPreferences? _prefs;

  /// Drops the cached handle so tests can load a fresh store.
  void debugReset() => _prefs = null;

  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> getString(String key) async => (await _p()).getString(key);

  Future<void> setString(String key, String value) async =>
      (await _p()).setString(key, value);

  Future<void> remove(String key) async => (await _p()).remove(key);

  Future<List<RetailOrder>> loadExtraOrders() async {
    final raw = await getString(extraOrders);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) RetailOrder.fromJson(item.cast<String, dynamic>()),
      ].whereType<RetailOrder>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveExtraOrders(List<RetailOrder> orders) async {
    await setString(
      extraOrders,
      jsonEncode([for (final o in orders) o.toJson()]),
    );
  }

  Future<List<String>> loadOutbox() async {
    final raw = await getString(outbox);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final id in list) id.toString()];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveOutbox(List<String> ids) async {
    await setString(outbox, jsonEncode(ids));
  }

  Future<List<PendingOperation>> loadPendingOperations() async {
    final raw = await getString(pendingOperations);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) PendingOperation.fromJson(item.cast<String, dynamic>()),
      ].whereType<PendingOperation>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingOperations(List<PendingOperation> operations) async {
    await setString(
      pendingOperations,
      jsonEncode([for (final op in operations) op.toJson()]),
    );
  }
}

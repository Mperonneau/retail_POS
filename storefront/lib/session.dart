import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Customer account for the vitrine. A guest can still order without one.
class Session extends ChangeNotifier {
  Session._();

  static final instance = Session._();
  static const _tokenKey = 'vitrine.account.token';
  static const _nameKey = 'vitrine.account.name';
  static const _phoneKey = 'vitrine.account.phone';
  static const _ordersKey = 'vitrine.local.orders';

  final _api = StorefrontApi();
  String token = '';
  String name = '';
  String phone = '';
  List<String> localOrderIds = [];

  bool get isLoggedIn => token.isNotEmpty && name.isNotEmpty;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey) ?? '';
    name = prefs.getString(_nameKey) ?? '';
    phone = prefs.getString(_phoneKey) ?? '';
    localOrderIds = prefs.getStringList(_ordersKey) ?? [];
    notifyListeners();
  }

  Future<void> login({
    required String phoneNumber,
    required String pin,
    String displayName = '',
  }) async {
    final account = await _api.login(phone: phoneNumber, pin: pin, name: displayName);
    token = account.token;
    name = account.name;
    phone = account.phone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_nameKey, name);
    await prefs.setString(_phoneKey, phone);
    notifyListeners();
  }

  Future<void> rename(String displayName) async {
    final account = await _api.renameAccount(token, displayName);
    name = account.name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
    notifyListeners();
  }

  Future<void> logout() async {
    token = '';
    name = '';
    phone = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_phoneKey);
    notifyListeners();
  }

  /// A devis or commande created on this device, guest or signed in.
  Future<void> rememberOrder(String id) async {
    if (id.isEmpty || localOrderIds.contains(id)) return;
    localOrderIds = [id, ...localOrderIds].take(40).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ordersKey, localOrderIds);
    notifyListeners();
  }

  Future<List<OrderSummary>> orders() async {
    final merged = <String, OrderSummary>{};
    if (isLoggedIn) {
      for (final row in await _api.orders(token)) {
        merged[row.id] = row;
      }
    }
    for (final id in localOrderIds) {
      if (merged.containsKey(id)) continue;
      try {
        merged[id] = OrderSummary.fromRequest(await _api.request(id));
      } on ApiException {
        // The free server may have forgotten a link. Skip it.
      }
    }
    final rows = merged.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }
}

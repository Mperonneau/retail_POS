import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Boutiques saved on this device. Works for a guest and for a signed-in customer.
class Favorites extends ChangeNotifier {
  Favorites._();

  static final instance = Favorites._();
  static const _key = 'vitrine.favorites';

  final List<ShopCard> shops = [];

  bool contains(String slug) => shops.any((shop) => shop.slug == slug);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    shops.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final row in list) {
            if (row is Map) {
              shops.add(ShopCard.fromJson(row.cast<String, dynamic>()));
            }
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggle(ShopCard shop) async {
    if (contains(shop.slug)) {
      shops.removeWhere((row) => row.slug == shop.slug);
    } else {
      shops.insert(0, shop);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([
        for (final row in shops)
          {
            'slug': row.slug,
            'name': row.name,
            'city': row.city,
            'department': row.department,
            'categories': row.categories,
            'description': row.description,
            'cover_url': row.coverUrl,
            'is_open_now': row.isOpenNow,
            'paused': row.paused,
            'opens_at_label': row.opensAtLabel,
          },
      ]),
    );
    notifyListeners();
  }
}

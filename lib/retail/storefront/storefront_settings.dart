import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/local_store.dart';
import 'business_categories.dart';

/// Public storefront site. Pass `--dart-define=STOREFRONT_URL=...` to override.
class StorefrontLinks {
  StorefrontLinks._();

  static const String base = String.fromEnvironment(
    'STOREFRONT_URL',
    defaultValue: 'https://retail-pos-vitrine.onrender.com',
  );

  static String get _root => base.replaceAll(RegExp(r'/+$'), '');

  static String get host => _root.replaceFirst(RegExp(r'^https?://'), '');

  static String shop(String slug) => '$_root/$slug';

  static String request(String id) => '$_root/r/$id';
}

final _slugPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$');

/// Official departments of Haiti, same list as the storefront directory.
const haitiDepartments = [
  'Artibonite',
  'Centre',
  "Grand'Anse",
  'Nippes',
  'Nord',
  'Nord-Est',
  'Nord-Ouest',
  'Ouest',
  'Sud',
  'Sud-Est',
];

bool isValidStorefrontSlug(String slug) => _slugPattern.hasMatch(slug);

/// Lowercase, accent-free, dash-separated link suggested from the shop name.
String suggestStorefrontSlug(String name) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'ñ': 'n',
  };
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(accents[char] ?? char);
  }
  var slug = buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 40) {
    slug = slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.length >= 3 ? slug : '';
}

class StorefrontSettings {
  const StorefrontSettings({
    this.loaded = false,
    this.enabled = false,
    this.paused = false,
    this.acceptWhenClosed = true,
    this.openHour = 8,
    this.closeHour = 18,
    this.closedWeekdays = const {7},
    this.slug = '',
    this.displayName = '',
    this.description = '',
    this.city = '',
    this.department = '',
    this.categories = const [],
    this.pickupNote = '',
    this.coverDataUrl,
    this.everPublished = false,
  });

  /// False until the saved settings have been read from the device.
  final bool loaded;
  final bool enabled;
  final bool paused;
  final bool acceptWhenClosed;
  final int openHour;
  final int closeHour;

  /// ISO weekdays, 1 = lundi … 7 = dimanche.
  final Set<int> closedWeekdays;
  final String slug;

  /// Name on the vitrine. Empty means the business name.
  final String displayName;
  final String description;
  final String city;
  final String department;

  /// Enterprise types. A shop can belong to several.
  final List<String> categories;
  final String pickupNote;
  final String? coverDataUrl;

  /// Once published, changes keep being sent so a disabled vitrine goes offline.
  final bool everPublished;

  StorefrontSettings copyWith({
    bool? loaded,
    bool? enabled,
    bool? paused,
    bool? acceptWhenClosed,
    int? openHour,
    int? closeHour,
    Set<int>? closedWeekdays,
    String? slug,
    String? displayName,
    String? description,
    String? city,
    String? department,
    List<String>? categories,
    String? pickupNote,
    Object? coverDataUrl = _keep,
    bool? everPublished,
  }) {
    return StorefrontSettings(
      loaded: loaded ?? this.loaded,
      enabled: enabled ?? this.enabled,
      paused: paused ?? this.paused,
      acceptWhenClosed: acceptWhenClosed ?? this.acceptWhenClosed,
      openHour: openHour ?? this.openHour,
      closeHour: closeHour ?? this.closeHour,
      closedWeekdays: closedWeekdays ?? this.closedWeekdays,
      slug: slug ?? this.slug,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      city: city ?? this.city,
      department: department ?? this.department,
      categories: categories ?? this.categories,
      pickupNote: pickupNote ?? this.pickupNote,
      coverDataUrl: coverDataUrl == _keep
          ? this.coverDataUrl
          : coverDataUrl as String?,
      everPublished: everPublished ?? this.everPublished,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'paused': paused,
    'acceptWhenClosed': acceptWhenClosed,
    'openHour': openHour,
    'closeHour': closeHour,
    'closedWeekdays': closedWeekdays.toList()..sort(),
    'slug': slug,
    'displayName': displayName,
    'description': description,
    'city': city,
    'department': department,
    'categories': categories,
    'pickupNote': pickupNote,
    'coverDataUrl': coverDataUrl,
    'everPublished': everPublished,
  };

  static StorefrontSettings fromJson(Map<String, dynamic> json) {
    int hour(Object? raw, int fallback) {
      final value = (raw as num?)?.toInt() ?? fallback;
      return value >= 0 && value <= 23 ? value : fallback;
    }

    return StorefrontSettings(
      loaded: true,
      enabled: json['enabled'] == true,
      paused: json['paused'] == true,
      acceptWhenClosed: json['acceptWhenClosed'] != false,
      openHour: hour(json['openHour'], 8),
      closeHour: hour(json['closeHour'], 18),
      closedWeekdays: {
        for (final day in (json['closedWeekdays'] as List? ?? const []))
          if (day is num && day >= 1 && day <= 7) day.toInt(),
      },
      slug: json['slug']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      department: haitiDepartments.contains(json['department'])
          ? json['department'] as String
          : '',
      categories: sanitizeBusinessCategories(json['categories']),
      pickupNote: json['pickupNote']?.toString() ?? '',
      coverDataUrl: (json['coverDataUrl'] as String?)?.isNotEmpty == true
          ? json['coverDataUrl'] as String
          : null,
      everPublished: json['everPublished'] == true,
    );
  }

  /// Mirrors the server: open now, given the hours and closed days.
  bool isOpenAt(DateTime now) {
    if (closedWeekdays.contains(now.weekday)) return false;
    if (openHour == closeHour) return true;
    if (openHour < closeHour) {
      return now.hour >= openHour && now.hour < closeHour;
    }
    return now.hour >= openHour || now.hour < closeHour;
  }
}

const Object _keep = Object();

class StorefrontSettingsNotifier extends StateNotifier<StorefrontSettings> {
  StorefrontSettingsNotifier() : super(const StorefrontSettings()) {
    Future<void>.microtask(_load);
  }

  static const _key = 'retail.storefront.settings';

  Future<void> _load() async {
    final raw = await LocalStore.instance.getString(_key);
    var loaded = const StorefrontSettings(loaded: true);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          loaded = StorefrontSettings.fromJson(json.cast<String, dynamic>());
        }
      } catch (_) {}
    }
    if (mounted) state = loaded;
  }

  void update(StorefrontSettings Function(StorefrontSettings current) change) {
    state = change(state).copyWith(loaded: true);
    LocalStore.instance.setString(_key, jsonEncode(state.toJson()));
  }
}

final storefrontSettingsProvider =
    StateNotifierProvider<StorefrontSettingsNotifier, StorefrontSettings>(
      (ref) => StorefrontSettingsNotifier(),
    );

/// Secret that proves this register owns its vitrine link on the server.
final storefrontShopKeyProvider = FutureProvider<String>((ref) async {
  const key = 'retail.storefront.shop_key';
  final saved = await LocalStore.instance.getString(key);
  if (saved != null && saved.length >= 32) return saved;
  final random = Random.secure();
  final created = List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await LocalStore.instance.setString(key, created);
  return created;
});

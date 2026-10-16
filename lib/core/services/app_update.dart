import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';
import 'page_reload.dart';

/// Compiled into the running build. Render sets this from the git commit.
const String kBuildId = String.fromEnvironment('BUILD_ID');

/// Matches the `+1` in pubspec until a deploy overrides it.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 1);

enum AppUpdateMode { none, soft, forced }

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.mode,
    this.versionKey = '',
    this.reload = true,
  });

  static const none = AppUpdateStatus(mode: AppUpdateMode.none);

  final AppUpdateMode mode;
  final String versionKey;
  final bool reload;

  @override
  bool operator ==(Object other) =>
      other is AppUpdateStatus &&
      other.mode == mode &&
      other.versionKey == versionKey &&
      other.reload == reload;

  @override
  int get hashCode => Object.hash(mode, versionKey, reload);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// Decides whether the running build should ask to reload.
///
/// Offline or a missing manifest means no banner.
AppUpdateStatus evaluateAppUpdate({
  required int buildNumber,
  required String buildId,
  Map<String, dynamic>? webManifest,
}) {
  if (webManifest == null) return AppUpdateStatus.none;
  final deployedId = '${webManifest['build_id'] ?? ''}'.trim();
  final deployedNumber = _asInt(webManifest['build_number']);
  final minBuild = _asInt(webManifest['min_build']);
  final key = 'web:${deployedId.isEmpty ? deployedNumber : deployedId}';
  if (buildNumber > 0 && minBuild > buildNumber && deployedNumber >= minBuild) {
    return AppUpdateStatus(
      mode: AppUpdateMode.forced,
      versionKey: key,
    );
  }
  if (buildId.isNotEmpty && deployedId.isNotEmpty && deployedId != buildId) {
    return AppUpdateStatus(mode: AppUpdateMode.soft, versionKey: key);
  }
  return AppUpdateStatus.none;
}

typedef JsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);

class AppUpdateChecker extends ChangeNotifier {
  AppUpdateChecker({
    int? buildNumber,
    String? buildId,
    JsonFetcher? fetch,
    Uri? manifestUri,
    bool enabled = true,
  })  : buildNumber = buildNumber ?? kBuildNumber,
        buildId = buildId ?? kBuildId,
        _fetch = fetch ?? _httpJson,
        _manifestUri = manifestUri,
        _enabled = enabled;

  final int buildNumber;
  final String buildId;
  final JsonFetcher _fetch;
  final Uri? _manifestUri;
  final bool _enabled;

  AppUpdateStatus _status = AppUpdateStatus.none;
  String? _dismissedKey;
  bool _checking = false;

  bool get enabled =>
      _enabled && (buildId.isNotEmpty || buildNumber > 0) && kIsWeb;

  AppUpdateStatus get visible {
    final status = _status;
    if (status.mode == AppUpdateMode.soft && status.versionKey == _dismissedKey) {
      return AppUpdateStatus.none;
    }
    return status;
  }

  Future<void> loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedKey = prefs.getString(LocalStore.updateDismissed);
  }

  Future<void> check() async {
    if (!enabled || _checking) return;
    _checking = true;
    try {
      if (_dismissedKey == null) await loadDismissed();
      final manifest = await _fetch(_manifestUri ?? _manifestLocation());
      _status = evaluateAppUpdate(
        buildNumber: buildNumber,
        buildId: buildId,
        webManifest: manifest,
      );
      notifyListeners();
    } finally {
      _checking = false;
    }
  }

  Future<void> dismiss() async {
    final key = _status.versionKey;
    if (key.isEmpty) return;
    _dismissedKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalStore.updateDismissed, key);
    notifyListeners();
  }

  Future<void> apply() => reloadApp();

  Uri _manifestLocation() {
    final base = Uri.base;
    return base.replace(
      path: base.path.endsWith('/') ? '${base.path}version.json' : '${base.path}/version.json',
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
    );
  }
}

Future<Map<String, dynamic>?> _httpJson(Uri uri) async {
  try {
    final response = await http
        .get(uri, headers: const {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return body is Map ? body.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

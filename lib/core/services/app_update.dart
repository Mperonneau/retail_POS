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

/// Returns a value that changes with every deploy, or null when offline.
typedef FingerprintFetcher = Future<String?> Function(Uri uri);

class AppUpdateChecker extends ChangeNotifier {
  AppUpdateChecker({
    int? buildNumber,
    String? buildId,
    JsonFetcher? fetch,
    FingerprintFetcher? fingerprint,
    Uri? manifestUri,
    bool enabled = true,
    bool? web,
  })  : buildNumber = buildNumber ?? kBuildNumber,
        buildId = buildId ?? kBuildId,
        _fetch = fetch ?? _httpJson,
        _fingerprint = fingerprint ?? _httpEtag,
        _manifestUri = manifestUri,
        _enabled = enabled,
        _web = web ?? kIsWeb;

  final int buildNumber;
  final String buildId;
  final JsonFetcher _fetch;
  final FingerprintFetcher _fingerprint;
  final Uri? _manifestUri;
  final bool _enabled;
  final bool _web;

  /// Fingerprint of the deploy this page loaded, when no build id was
  /// compiled in.
  String? _loadedFingerprint;

  AppUpdateStatus _status = AppUpdateStatus.none;
  String? _dismissedKey;
  bool _checking = false;

  bool get enabled => _enabled && _web;

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
      final manifest = await _fetch(_manifestUri ?? _resolve('version.json'));
      var status = evaluateAppUpdate(
        buildNumber: buildNumber,
        buildId: buildId,
        webManifest: manifest,
      );
      if (status.mode == AppUpdateMode.none && buildId.isEmpty) {
        status = await _checkFingerprint();
      }
      if (status != _status) {
        _status = status;
        notifyListeners();
      }
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

  /// The deploy has no build id: compare the ETag of `main.dart.js` with
  /// the one seen when this page started.
  Future<AppUpdateStatus> _checkFingerprint() async {
    final current = await _fingerprint(_resolve('main.dart.js'));
    if (current == null || current.isEmpty) return _status;
    final loaded = _loadedFingerprint ??= current;
    if (current == loaded) return AppUpdateStatus.none;
    return AppUpdateStatus(mode: AppUpdateMode.soft, versionKey: 'web:$current');
  }

  Uri _resolve(String file) {
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/$file',
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
    );
  }
}

Future<String?> _httpEtag(Uri uri) async {
  try {
    final response = await http
        .head(uri, headers: const {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final etag = response.headers['etag'] ?? response.headers['last-modified'];
    if (etag != null && etag.isNotEmpty) return etag;
    return response.headers['content-length'];
  } catch (_) {
    return null;
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

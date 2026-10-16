import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-app toast style: success, neutral info, warning, error.
enum AppNotificationKind { success, info, warning, error }

class AppNotificationData {
  final String message;
  final AppNotificationKind kind;
  final int token;

  const AppNotificationData({
    required this.message,
    required this.kind,
    required this.token,
  });
}

/// Global notification shown at the **top of the main content** (below the app top bar)
/// so staff see confirmations immediately — replaces easy-to-miss bottom SnackBars.
final appNotificationProvider =
    NotifierProvider<AppNotificationNotifier, AppNotificationData?>(
  AppNotificationNotifier.new,
);

class AppNotificationNotifier extends Notifier<AppNotificationData?> {
  Timer? _timer;
  int _seq = 0;

  @override
  AppNotificationData? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(
    String message, {
    AppNotificationKind kind = AppNotificationKind.success,
    Duration duration = const Duration(seconds: 4),
  }) {
    _timer?.cancel();
    final token = ++_seq;
    state = AppNotificationData(message: message, kind: kind, token: token);
    _timer = Timer(duration, () {
      if (state?.token == token) {
        state = null;
      }
    });
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

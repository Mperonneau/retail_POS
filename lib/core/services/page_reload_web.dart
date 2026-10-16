import 'dart:js_interop';

import 'package:web/web.dart';

/// Drops the cached app, then loads the deploy that is on the server now.
Future<void> reloadApp() async {
  try {
    final registrations = await window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final registration in registrations.toDart) {
      await registration.unregister().toDart;
    }
  } catch (_) {}
  window.location.reload();
}

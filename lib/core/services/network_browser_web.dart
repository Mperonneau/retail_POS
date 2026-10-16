import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

class BrowserNetwork {
  static bool get isOnline => window.navigator.onLine;

  static Stream<bool> get changes {
    final controller = StreamController<bool>.broadcast();
    window.addEventListener(
      'online',
      ((Event _) => controller.add(true)).toJS,
    );
    window.addEventListener(
      'offline',
      ((Event _) => controller.add(false)).toJS,
    );
    return controller.stream;
  }
}

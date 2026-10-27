import 'dart:ui';

import 'package:web/web.dart' as web;

String? _painted;

/// Paints the strip the phone shows above the app (status bar, notch) in [color].
///
/// Flutter web reports no top safe-area inset, so the browser draws that strip
/// from the page background and the theme-color tag.
void paintBrowserChrome(Color color) {
  final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  if (_painted == hex) return;
  _painted = hex;
  web.document.documentElement?.setAttribute('style', 'background:$hex');
  web.document.body?.style.background = hex;
  final metas = web.document.querySelectorAll('meta[name="theme-color"]');
  if (metas.length == 0) {
    final meta = web.document.createElement('meta') as web.HTMLMetaElement
      ..name = 'theme-color'
      ..content = hex;
    web.document.head?.append(meta);
    return;
  }
  for (var i = 0; i < metas.length; i++) {
    (metas.item(i) as web.HTMLMetaElement).content = hex;
  }
}

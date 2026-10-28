import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Sends the message and the link together, so WhatsApp shows the text with
/// the shop card under it. False when this browser cannot share a link.
Future<bool> shareLinkWithMessage(String message, String url) async {
  final data = web.ShareData(text: message, url: url);
  final navigator = web.window.navigator;
  try {
    if (!navigator.canShare(data)) return false;
  } catch (_) {
    return false;
  }
  try {
    await navigator.share(data).toDart;
  } catch (error) {
    // Closing the share sheet without choosing an app is not a failure.
    if (!'$error'.contains('AbortError')) rethrow;
  }
  return true;
}

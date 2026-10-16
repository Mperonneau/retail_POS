/// Tests and desktop builds start online. The session can still be
/// marked offline by [DeviceSessionNotifier.debugSetOnline].
class BrowserNetwork {
  static bool get isOnline => true;

  static Stream<bool> get changes => const Stream<bool>.empty();
}

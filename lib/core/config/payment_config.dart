/// Payment gateway settings for the retail app.
///
/// Pass values at build time. Do not commit live secrets.
///
/// ```
/// flutter run \
///   --dart-define=MONCASH_CLIENT_ID=... \
///   --dart-define=MONCASH_SECRET_KEY=... \
///   --dart-define=MONCASH_MODE=sandbox \
///   --dart-define=STRIPE_PUBLISHABLE_KEY=...
/// ```
///
/// MonCash and Stripe secret keys used to charge cards belong on the
/// server. [moncashSecretKey] is only here so a future local gateway
/// client can read the same define the backend uses during development.
class PaymentConfig {
  static const moncashClientId = String.fromEnvironment('MONCASH_CLIENT_ID');
  static const moncashSecretKey = String.fromEnvironment('MONCASH_SECRET_KEY');
  static const moncashMode = String.fromEnvironment(
    'MONCASH_MODE',
    defaultValue: 'sandbox',
  );
  static const stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  static bool get isMoncashLive => moncashMode == 'live';
}

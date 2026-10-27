import 'payments_client.dart';

/// Holds the mounted Stripe card element so the pay button can confirm it.
///
/// The card number never passes through this object. Stripe.js keeps it and
/// only a PaymentIntent client secret is sent to [confirmPayment].
class StripeCardController {
  Future<void> Function(String clientSecret)? _confirm;

  bool get isReady => _confirm != null;

  void attach(Future<void> Function(String clientSecret) confirm) {
    _confirm = confirm;
  }

  void detach() {
    _confirm = null;
  }

  Future<void> confirmPayment(String clientSecret) {
    final confirm = _confirm;
    if (confirm == null) {
      throw PaymentsException('Le formulaire carte n\'est pas prêt.');
    }
    return confirm(clientSecret);
  }
}

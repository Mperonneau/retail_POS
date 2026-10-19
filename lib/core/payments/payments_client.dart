import 'dart:convert';

import 'package:http/http.dart' as http;

import 'card_charge_pricing.dart';

/// Talks to the payments server. The Flutter app never holds a Stripe secret
/// or a MonCash secret — those stay in the server environment.
class PaymentsException implements Exception {
  PaymentsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class HostedCheckout {
  const HostedCheckout({
    required this.id,
    required this.url,
    required this.pricing,
  });

  final String id;
  final String url;
  final CardChargePricing pricing;
}

class PaymentsPublicConfig {
  const PaymentsPublicConfig({
    required this.stripeConfigured,
    required this.publishableKey,
  });

  final bool stripeConfigured;
  final String publishableKey;
}

class CardPaymentIntent {
  const CardPaymentIntent({
    required this.id,
    required this.clientSecret,
    required this.pricing,
  });

  final String id;
  final String clientSecret;
  final CardChargePricing pricing;
}

class MoncashCheckout {
  const MoncashCheckout({
    required this.orderId,
    required this.paymentUrl,
    required this.amountHtg,
  });

  final String orderId;
  final String paymentUrl;
  final int amountHtg;
}

class PaymentsClient {
  PaymentsClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _ownsClient = httpClient == null,
      baseUrl = (baseUrl ?? apiBase).trim();

  /// Used when the web build does not pass `--dart-define=PAYMENTS_API`.
  /// Render's saved build command omits that flag, so the register must
  /// still know where the payments service lives. Secrets stay on the server.
  static const String apiBase = String.fromEnvironment(
    'PAYMENTS_API',
    defaultValue: 'https://retail-pos-payments.onrender.com',
  );

  final http.Client _http;
  final bool _ownsClient;
  final String baseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;

  void close() {
    if (_ownsClient) _http.close();
  }

  Uri _uri(String path) {
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root$path');
  }

  Future<HostedCheckout> createCheckout({
    required String reference,
    required int orderUsdCents,
    required String description,
    String recipientName = '',
    String recipientEmail = '',
    String recipientPhone = '',
  }) async {
    _requireConfigured();
    final body = await _post('/payments/checkout', {
      'reference': reference,
      'order_usd_cents': orderUsdCents,
      'description': description,
      'recipient_name': recipientName,
      'recipient_email': recipientEmail,
      'recipient_phone': recipientPhone,
    });
    final pricing = _pricing(body);
    final url = (body['url'] as String?)?.trim() ?? '';
    final id = (body['id'] as String?)?.trim() ?? '';
    if (url.isEmpty || id.isEmpty) {
      throw PaymentsException('Stripe n\'a pas renvoyé de lien de paiement.');
    }
    return HostedCheckout(id: id, url: url, pricing: pricing);
  }

  Future<bool> checkoutPaid(String sessionId) async {
    _requireConfigured();
    final body = await _get('/payments/checkout/$sessionId');
    return body['paid'] == true;
  }

  Future<PaymentsPublicConfig> fetchConfig() async {
    _requireConfigured();
    final body = await _get('/config');
    return PaymentsPublicConfig(
      stripeConfigured: body['stripe_configured'] == true,
      publishableKey: (body['publishable_key'] as String?)?.trim() ?? '',
    );
  }

  /// PaymentIntent for the in-app card form. [CardPaymentIntent.clientSecret]
  /// is handed to Stripe.js and is not a card number.
  Future<CardPaymentIntent> createCardIntent({
    required String reference,
    required int orderUsdCents,
    required String description,
  }) async {
    _requireConfigured();
    final body = await _post('/payments/intent', {
      'reference': reference,
      'order_usd_cents': orderUsdCents,
      'description': description,
    });
    final id = (body['id'] as String?)?.trim() ?? '';
    final clientSecret = (body['client_secret'] as String?)?.trim() ?? '';
    if (id.isEmpty || clientSecret.isEmpty) {
      throw PaymentsException('Stripe n\'a pas renvoyé de paiement.');
    }
    return CardPaymentIntent(
      id: id,
      clientSecret: clientSecret,
      pricing: _pricing(body),
    );
  }

  Future<bool> cardIntentPaid(String intentId) async {
    _requireConfigured();
    final body = await _get('/payments/intent/$intentId');
    return body['paid'] == true;
  }

  CardChargePricing _pricing(Map<String, dynamic> body) {
    return CardChargePricing(
      orderUsdCents: _int(body['order_usd_cents']),
      platformFeeUsdCents: _int(body['platform_fee_usd_cents']),
      stripeFeeUsdCents: _int(body['stripe_fee_usd_cents']),
      totalUsdCents: _int(body['total_usd_cents']),
    );
  }

  Future<MoncashCheckout> createMoncash({
    required String orderId,
    required int amountHtg,
  }) async {
    _requireConfigured();
    final body = await _post('/payments/moncash', {
      'order_id': orderId,
      'amount_htg': amountHtg,
    });
    final url = (body['payment_url'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      throw PaymentsException('MonCash n\'a pas renvoyé de page de paiement.');
    }
    return MoncashCheckout(
      orderId: (body['order_id'] as String?)?.trim().isNotEmpty == true
          ? (body['order_id'] as String).trim()
          : orderId,
      paymentUrl: url,
      amountHtg: _int(body['amount_htg']),
    );
  }

  Future<bool> moncashPaid(String orderId) async {
    _requireConfigured();
    final body = await _get('/payments/moncash/$orderId');
    return body['paid'] == true;
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw PaymentsException(
        'Le serveur de paiement n\'est pas configuré. '
        'Ajoutez PAYMENTS_API au build, puis STRIPE_SECRET_KEY '
        'et les clés MonCash sur le service Render.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw PaymentsException(
        'Impossible de joindre le serveur de paiement. Vérifiez la connexion.',
      );
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final http.Response response;
    try {
      response = await _http
          .get(_uri(path))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw PaymentsException(
        'Impossible de joindre le serveur de paiement. Vérifiez la connexion.',
      );
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = const {};
      }
    }
    if (response.statusCode >= 400) {
      final message = (body['error'] as String?)?.trim();
      throw PaymentsException(
        message == null || message.isEmpty
            ? 'Le paiement a échoué (${response.statusCode}).'
            : message,
      );
    }
    return body;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}

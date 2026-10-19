import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/payments/payments_client.dart';

class StorefrontApiException implements Exception {
  StorefrontApiException(this.message, {this.status = 0});
  final String message;
  final int status;

  @override
  String toString() => message;
}

class StorefrontPublishResult {
  const StorefrontPublishResult({
    required this.slug,
    required this.productCount,
    required this.missingPhotos,
  });

  final String slug;
  final int productCount;
  final List<String> missingPhotos;
}

class StorefrontInboxLine {
  const StorefrontInboxLine({
    required this.productId,
    required this.name,
    required this.optionsLabel,
    required this.quantity,
    required this.unitHtg,
  });

  final String productId;
  final String name;
  final String optionsLabel;
  final int quantity;
  final double unitHtg;

  String get displayName =>
      optionsLabel.isEmpty ? name : '$name ($optionsLabel)';
}

/// A devis or commande received from the vitrine (or shared from the POS).
class StorefrontInboxRequest {
  const StorefrontInboxRequest({
    required this.id,
    required this.number,
    required this.kind,
    required this.status,
    required this.source,
    required this.externalRef,
    required this.createdAt,
    required this.paidAt,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.note,
    required this.lines,
    required this.discountHtg,
    required this.totalHtg,
    required this.paymentMethod,
    required this.paymentReference,
  });

  final String id;
  final String number;
  final String kind;
  final String status;
  final String source;
  final String externalRef;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String note;
  final List<StorefrontInboxLine> lines;
  final double discountHtg;
  final double totalHtg;
  final String paymentMethod;
  final String paymentReference;

  bool get isPaid => status == 'paid';
  bool get isQuote => kind == 'devis';
  bool get fromRegister => source == 'pos';

  static StorefrontInboxRequest fromJson(Map<String, dynamic> json) {
    DateTime? stamp(Object? raw) {
      final seconds = (raw as num?)?.toInt() ?? 0;
      return seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null;
    }

    final customer = (json['customer'] as Map?)?.cast<String, dynamic>() ?? {};
    final payment = (json['payment'] as Map?)?.cast<String, dynamic>() ?? {};
    return StorefrontInboxRequest(
      id: json['id']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'commande',
      status: json['status']?.toString() ?? 'open',
      source: json['source']?.toString() ?? 'storefront',
      externalRef: json['external_ref']?.toString() ?? '',
      createdAt: stamp(json['created_at']) ?? DateTime.now(),
      paidAt: stamp(json['paid_at']),
      customerName: customer['name']?.toString() ?? '',
      customerPhone: customer['phone']?.toString() ?? '',
      customerEmail: customer['email']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      lines: [
        for (final raw in (json['lines'] as List? ?? const []))
          if (raw is Map)
            StorefrontInboxLine(
              productId: raw['product_id']?.toString() ?? '',
              name: raw['name']?.toString() ?? '',
              optionsLabel: raw['options_label']?.toString() ?? '',
              quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
              unitHtg: (raw['unit_htg'] as num?)?.toDouble() ?? 0,
            ),
      ],
      discountHtg: (json['discount_htg'] as num?)?.toDouble() ?? 0,
      totalHtg: (json['total_htg'] as num?)?.toDouble() ?? 0,
      paymentMethod: payment['method']?.toString() ?? '',
      paymentReference: payment['reference']?.toString() ?? '',
    );
  }
}

/// Shop-side calls to the vitrine API on the payments server.
class StorefrontApi {
  StorefrontApi({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = (baseUrl ?? PaymentsClient.apiBase).trim();

  final http.Client _http;
  final String baseUrl;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<StorefrontPublishResult> publish(
    String shopKey,
    Map<String, dynamic> payload,
  ) async {
    final body = await _send(
      'POST',
      '/storefront/shop/publish',
      shopKey,
      payload,
      timeout: const Duration(seconds: 90),
    );
    return StorefrontPublishResult(
      slug: body['slug']?.toString() ?? '',
      productCount: (body['products'] as num?)?.toInt() ?? 0,
      missingPhotos: [
        for (final p in (body['missing_photos'] as List? ?? const [])) '$p',
      ],
    );
  }

  Future<bool> slugAvailable(String shopKey, String slug) async {
    final body = await _send(
      'GET',
      '/storefront/shop/slug?slug=${Uri.encodeQueryComponent(slug)}',
      shopKey,
      null,
    );
    return body['available'] == true;
  }

  Future<List<StorefrontInboxRequest>> inbox(String shopKey) async {
    final body = await _send('GET', '/storefront/shop/inbox', shopKey, null);
    return [
      for (final raw in (body['requests'] as List? ?? const []))
        if (raw is Map)
          StorefrontInboxRequest.fromJson(raw.cast<String, dynamic>()),
    ];
  }

  /// Creates (or refreshes) a shareable pay link for a devis made at the register.
  Future<String> shareRequest(
    String shopKey,
    Map<String, dynamic> payload,
  ) async {
    final body =
        await _send('POST', '/storefront/shop/requests', shopKey, payload);
    final id = body['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw StorefrontApiException('Le serveur n\'a pas renvoyé de lien.');
    }
    return id;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String shopKey,
    Map<String, dynamic>? payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final headers = {
      'X-Shop-Key': shopKey,
      if (payload != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      response = await (method == 'GET'
              ? _http.get(_uri(path), headers: headers)
              : _http.post(
                  _uri(path),
                  headers: headers,
                  body: jsonEncode(payload ?? const {}),
                ))
          .timeout(timeout);
    } catch (_) {
      throw StorefrontApiException(
        'Impossible de joindre le serveur de la vitrine.',
      );
    }
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
    }
    if (response.statusCode >= 400) {
      final message = body['error']?.toString().trim() ?? '';
      throw StorefrontApiException(
        message.isEmpty
            ? 'La vitrine a répondu ${response.statusCode}.'
            : message,
        status: response.statusCode,
      );
    }
    return body;
  }
}

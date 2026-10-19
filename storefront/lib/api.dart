import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retail_pos/core/payments/card_charge_pricing.dart';

/// Vitrine API on the payments server. No secret ever reaches this app.
class StorefrontApi {
  StorefrontApi({http.Client? client}) : _http = client ?? http.Client();

  static const String base = String.fromEnvironment(
    'STOREFRONT_API',
    defaultValue: 'https://retail-pos-payments.onrender.com',
  );

  final http.Client _http;

  static String get _root => base.replaceAll(RegExp(r'/+$'), '');

  /// Photo paths from the server are relative to the API.
  static String photo(String path) =>
      path.isEmpty || path.startsWith('http') ? path : '$_root$path';

  Future<ShopDirectory> directory() async =>
      ShopDirectory.fromJson(await _get('/storefront/shops'));

  Future<CustomerAccount> login({
    required String phone,
    required String pin,
    String name = '',
  }) async {
    final body = await _post('/storefront/account/login', {
      'phone': phone,
      'pin': pin,
      'name': name,
    });
    final account = (body['account'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CustomerAccount(
      token: body['token']?.toString() ?? '',
      name: account['name']?.toString() ?? '',
      phone: account['phone']?.toString() ?? phone,
    );
  }

  Future<CustomerAccount> renameAccount(String token, String name) async {
    final body = await _send(() => _http.post(
          Uri.parse('$_root/storefront/account'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'name': name}),
        ));
    final account = (body['account'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CustomerAccount(
      token: token,
      name: account['name']?.toString() ?? name,
      phone: account['phone']?.toString() ?? '',
    );
  }

  Future<List<OrderSummary>> orders(String token) async {
    final body = await _get('/storefront/account/orders', token: token);
    return [
      for (final row in (body['orders'] as List? ?? const []))
        if (row is Map) OrderSummary.fromJson(row.cast<String, dynamic>()),
    ];
  }

  Future<Shop> shop(String slug) async =>
      Shop.fromJson(await _get('/storefront/shops/${Uri.encodeComponent(slug)}'));

  Future<RequestView> submit({
    required String slug,
    required String kind,
    required List<Map<String, dynamic>> lines,
    required String name,
    required String phone,
    required String email,
    required String note,
    String? token,
  }) async {
    final body = await _post(
      '/storefront/shops/${Uri.encodeComponent(slug)}/requests',
      {
        'kind': kind,
        'lines': lines,
        'customer': {'name': name, 'phone': phone, 'email': email},
        'note': note,
      },
      token: token,
    );
    return RequestView.fromJson(body);
  }

  Future<RequestView> request(String id) async =>
      RequestView.fromJson(await _get('/storefront/requests/$id'));

  Future<CardIntent> startCard(String id) async {
    final body = await _post('/storefront/requests/$id/card', const {});
    return CardIntent(
      id: body['id']?.toString() ?? '',
      clientSecret: body['client_secret']?.toString() ?? '',
      publishableKey: body['publishable_key']?.toString() ?? '',
      pricing: CardChargePricing(
        orderUsdCents: _int(body['order_usd_cents']),
        platformFeeUsdCents: _int(body['platform_fee_usd_cents']),
        stripeFeeUsdCents: _int(body['stripe_fee_usd_cents']),
        totalUsdCents: _int(body['total_usd_cents']),
      ),
    );
  }

  Future<RequestView> confirmCard(String id, String intentId) async =>
      RequestView.fromJson(
        await _post('/storefront/requests/$id/card/confirm', {'intent_id': intentId}),
      );

  Future<MoncashStart> startMoncash(String id) async {
    final body = await _post('/storefront/requests/$id/moncash', const {});
    return MoncashStart(
      paymentUrl: body['payment_url']?.toString() ?? '',
      amountHtg: _int(body['amount_htg']),
    );
  }

  /// Returns the paid request, or null while MonCash has not confirmed.
  Future<RequestView?> moncashStatus(String id) async {
    final body = await _get('/storefront/requests/$id/moncash');
    if (body['paid'] != true) return null;
    final raw = body['request'];
    return raw is Map<String, dynamic> ? RequestView.fromJson(raw) : null;
  }

  Future<Map<String, dynamic>> _get(String path, {String? token}) =>
      _send(() => _http.get(Uri.parse('$_root$path'), headers: _auth(token)));

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) =>
      _send(() => _http.post(
            Uri.parse('$_root$path'),
            headers: {'Content-Type': 'application/json', ..._auth(token)},
            body: jsonEncode(payload),
          ));

  Map<String, String> _auth(String? token) =>
      token == null || token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ApiException('Connexion impossible. Vérifiez votre réseau et réessayez.');
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (response.statusCode >= 400) {
      final message = body['error']?.toString().trim() ?? '';
      throw ApiException(
        message.isEmpty ? 'Une erreur est survenue (${response.statusCode}).' : message,
        status: response.statusCode,
      );
    }
    return body;
  }
}

int _int(Object? value) => value is num ? value.round() : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0});
  final String message;
  final int status;

  @override
  String toString() => message;
}

class Availability {
  const Availability({
    required this.isOpenNow,
    required this.paused,
    required this.acceptsOrders,
    required this.acceptsQuotes,
    required this.opensAtLabel,
    required this.openHour,
    required this.closeHour,
    required this.closedWeekdays,
  });

  final bool isOpenNow;
  final bool paused;
  final bool acceptsOrders;
  final bool acceptsQuotes;
  final String? opensAtLabel;
  final int openHour;
  final int closeHour;
  final List<int> closedWeekdays;

  factory Availability.fromJson(Map<String, dynamic> json) => Availability(
        isOpenNow: json['is_open_now'] == true,
        paused: json['paused'] == true,
        acceptsOrders: json['accepts_orders'] == true,
        acceptsQuotes: json['accepts_quotes'] == true,
        opensAtLabel: json['opens_at_label']?.toString(),
        openHour: _int(json['open_hour']),
        closeHour: _int(json['close_hour']),
        closedWeekdays: [
          for (final d in (json['closed_weekdays'] as List? ?? const [])) _int(d),
        ],
      );
}

class OptionChoice {
  const OptionChoice({required this.id, required this.name, required this.deltaHtg});
  final String id;
  final String name;
  final double deltaHtg;
}

class OptionGroup {
  const OptionGroup({
    required this.id,
    required this.name,
    required this.required,
    required this.multiple,
    required this.choices,
  });

  final String id;
  final String name;
  final bool required;
  final bool multiple;
  final List<OptionChoice> choices;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.priceHtg,
    required this.regularPriceHtg,
    required this.photoUrl,
    required this.available,
    required this.maxQuantity,
    required this.unit,
    required this.options,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final double priceHtg;
  final double regularPriceHtg;
  final String photoUrl;
  final bool available;
  final int maxQuantity;
  final String unit;
  final List<OptionGroup> options;

  bool get onSale => regularPriceHtg > priceHtg;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priceHtg: _double(json['price_htg']),
        regularPriceHtg: _double(json['regular_price_htg']),
        photoUrl: StorefrontApi.photo(json['photo_url']?.toString() ?? ''),
        available: json['available'] == true,
        maxQuantity: _int(json['max_quantity']),
        unit: json['unit']?.toString() ?? '',
        options: [
          for (final g in (json['options'] as List? ?? const []))
            if (g is Map)
              OptionGroup(
                id: g['id']?.toString() ?? '',
                name: g['name']?.toString() ?? '',
                required: g['required'] == true,
                multiple: g['multiple'] == true,
                choices: [
                  for (final c in (g['choices'] as List? ?? const []))
                    if (c is Map)
                      OptionChoice(
                        id: c['id']?.toString() ?? '',
                        name: c['name']?.toString() ?? '',
                        deltaHtg: _double(c['delta_htg']),
                      ),
                ],
              ),
        ],
      );
}

class CustomerAccount {
  const CustomerAccount({required this.token, required this.name, required this.phone});

  final String token;
  final String name;
  final String phone;
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.shopName,
    required this.shopSlug,
    required this.totalHtg,
    required this.usdRate,
  });

  final String id;
  final String number;
  final String kind;
  final String status;
  final int createdAt;
  final String shopName;
  final String shopSlug;
  final double totalHtg;
  final double usdRate;

  bool get isPaid => status == 'paid';
  bool get isQuote => kind == 'devis';

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: json['id']?.toString() ?? '',
        number: json['number']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        createdAt: _int(json['created_at']),
        shopName: json['shop_name']?.toString() ?? '',
        shopSlug: json['shop_slug']?.toString() ?? '',
        totalHtg: _double(json['total_htg']),
        usdRate: _double(json['usd_rate']),
      );

  factory OrderSummary.fromRequest(RequestView request) => OrderSummary(
        id: request.id,
        number: request.number,
        kind: request.kind,
        status: request.status,
        createdAt: request.createdAt.millisecondsSinceEpoch ~/ 1000,
        shopName: request.shopName,
        shopSlug: '',
        totalHtg: request.totalHtg,
        usdRate: request.usdRate,
      );
}

class ShopCard {
  const ShopCard({
    required this.slug,
    required this.name,
    required this.city,
    required this.department,
    required this.description,
    required this.coverUrl,
    required this.isOpenNow,
    required this.paused,
    required this.opensAtLabel,
  });

  final String slug;
  final String name;
  final String city;
  final String department;
  final String description;
  final String coverUrl;
  final bool isOpenNow;
  final bool paused;
  final String opensAtLabel;

  String get place => [city, department].where((part) => part.isNotEmpty).join(', ');

  factory ShopCard.fromJson(Map<String, dynamic> json) => ShopCard(
        slug: json['slug']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        city: json['city']?.toString() ?? '',
        department: json['department']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        coverUrl: StorefrontApi.photo(json['cover_url']?.toString() ?? ''),
        isOpenNow: json['is_open_now'] == true,
        paused: json['paused'] == true,
        opensAtLabel: json['opens_at_label']?.toString() ?? '',
      );
}

class ShopDirectory {
  const ShopDirectory({required this.results, required this.departments});

  final List<ShopCard> results;
  final List<String> departments;

  factory ShopDirectory.fromJson(Map<String, dynamic> json) => ShopDirectory(
        results: [
          for (final row in (json['results'] as List? ?? const []))
            if (row is Map) ShopCard.fromJson(row.cast<String, dynamic>()),
        ],
        departments: [
          for (final name in (json['departments'] as List? ?? const [])) '$name',
        ],
      );
}

class Shop {
  const Shop({
    required this.slug,
    required this.name,
    required this.phone,
    required this.address,
    this.city = '',
    this.department = '',
    required this.description,
    required this.pickupNote,
    required this.coverUrl,
    required this.usdRate,
    required this.availability,
    required this.categories,
    required this.products,
  });

  final String slug;
  final String name;
  final String phone;
  final String address;
  final String city;
  final String department;
  final String description;
  final String pickupNote;
  final String coverUrl;

  /// HTG per 1 USD.
  final double usdRate;
  final Availability availability;
  final List<String> categories;
  final List<Product> products;

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        slug: json['slug']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        city: json['city']?.toString() ?? '',
        department: json['department']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        pickupNote: json['pickup_note']?.toString() ?? '',
        coverUrl: StorefrontApi.photo(json['cover_url']?.toString() ?? ''),
        usdRate: _double(json['usd_rate']),
        availability: Availability.fromJson(
          (json['availability'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        categories: [for (final c in (json['categories'] as List? ?? const [])) '$c'],
        products: [
          for (final p in (json['products'] as List? ?? const []))
            if (p is Map) Product.fromJson(p.cast<String, dynamic>()),
        ],
      );
}

class RequestLine {
  const RequestLine({
    required this.name,
    required this.optionsLabel,
    required this.quantity,
    required this.unitHtg,
    required this.totalHtg,
  });

  final String name;
  final String optionsLabel;
  final int quantity;
  final double unitHtg;
  final double totalHtg;
}

/// A devis or commande behind a shareable link.
class RequestView {
  const RequestView({
    required this.id,
    required this.number,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.paymentMethod,
    required this.customerName,
    required this.note,
    required this.lines,
    required this.discountHtg,
    required this.totalHtg,
    required this.usdRate,
    required this.orderUsdCents,
    required this.moncashHtg,
    required this.shopSlug,
    required this.shopName,
    required this.shopPhone,
    required this.pickupNote,
    required this.coverUrl,
  });

  final String id;
  final String number;
  final String kind;
  final String status;
  final DateTime createdAt;
  final String paymentMethod;
  final String customerName;
  final String note;
  final List<RequestLine> lines;
  final double discountHtg;
  final double totalHtg;
  final double usdRate;
  final int orderUsdCents;
  final int moncashHtg;
  final String shopSlug;
  final String shopName;
  final String shopPhone;
  final String pickupNote;
  final String coverUrl;

  bool get isPaid => status == 'paid';
  bool get isQuote => kind == 'devis';

  factory RequestView.fromJson(Map<String, dynamic> json) {
    final shop = (json['shop'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RequestView(
      id: json['id']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'commande',
      status: json['status']?.toString() ?? 'open',
      createdAt: DateTime.fromMillisecondsSinceEpoch(_int(json['created_at']) * 1000),
      paymentMethod: json['payment_method']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      lines: [
        for (final l in (json['lines'] as List? ?? const []))
          if (l is Map)
            RequestLine(
              name: l['name']?.toString() ?? '',
              optionsLabel: l['options_label']?.toString() ?? '',
              quantity: _int(l['quantity']),
              unitHtg: _double(l['unit_htg']),
              totalHtg: _double(l['total_htg']),
            ),
      ],
      discountHtg: _double(json['discount_htg']),
      totalHtg: _double(json['total_htg']),
      usdRate: _double(json['usd_rate']),
      orderUsdCents: _int(json['order_usd_cents']),
      moncashHtg: _int(json['moncash_htg']),
      shopSlug: shop['slug']?.toString() ?? '',
      shopName: shop['name']?.toString() ?? '',
      shopPhone: shop['phone']?.toString() ?? '',
      pickupNote: shop['pickup_note']?.toString() ?? '',
      coverUrl: StorefrontApi.photo(shop['cover_url']?.toString() ?? ''),
    );
  }
}

class CardIntent {
  const CardIntent({
    required this.id,
    required this.clientSecret,
    required this.publishableKey,
    required this.pricing,
  });

  final String id;
  final String clientSecret;
  final String publishableKey;
  final CardChargePricing pricing;
}

class MoncashStart {
  const MoncashStart({required this.paymentUrl, required this.amountHtg});
  final String paymentUrl;
  final int amountHtg;
}

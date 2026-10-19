import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/mock/mock_retail_orders.dart';
import '../../core/models/order_history.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import '../../core/providers/app_notification_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/currency_settings_provider.dart';
import 'storefront_api.dart';
import 'storefront_settings.dart';

class StorefrontSyncState {
  const StorefrontSyncState({
    this.publishing = false,
    this.publishedAt,
    this.error,
    this.slugTaken = false,
    this.inboxAt,
    this.openQuotes = 0,
    this.paidOrders = 0,
  });

  final bool publishing;
  final DateTime? publishedAt;
  final String? error;
  final bool slugTaken;
  final DateTime? inboxAt;

  /// Devis received from the vitrine and not paid yet.
  final int openQuotes;

  /// Paid vitrine requests listed by the server.
  final int paidOrders;

  StorefrontSyncState copyWith({
    bool? publishing,
    DateTime? publishedAt,
    Object? error = _keep,
    bool? slugTaken,
    DateTime? inboxAt,
    int? openQuotes,
    int? paidOrders,
  }) {
    return StorefrontSyncState(
      publishing: publishing ?? this.publishing,
      publishedAt: publishedAt ?? this.publishedAt,
      error: error == _keep ? this.error : error as String?,
      slugTaken: slugTaken ?? this.slugTaken,
      inboxAt: inboxAt ?? this.inboxAt,
      openQuotes: openQuotes ?? this.openQuotes,
      paidOrders: paidOrders ?? this.paidOrders,
    );
  }
}

const Object _keep = Object();

/// Publishes the vitrine when settings or the catalog change, and imports
/// devis and paid orders from the server into Devis and Commandes.
class StorefrontSyncNotifier extends StateNotifier<StorefrontSyncState> {
  StorefrontSyncNotifier(this._ref, {StorefrontApi? api})
      : _api = api ?? StorefrontApi(),
        super(const StorefrontSyncState());

  final Ref _ref;
  final StorefrontApi _api;
  Timer? _debounce;
  Timer? _poll;
  bool _running = false;
  bool _dirty = false;
  bool _firstPull = true;

  /// Photo paths the server already holds, so they are not re-uploaded.
  final Set<String> _uploaded = {};

  static const pollEvery = Duration(seconds: 30);

  StorefrontSettings get _settings => _ref.read(storefrontSettingsProvider);

  bool get _shouldPublish {
    final s = _settings;
    return s.loaded &&
        isValidStorefrontSlug(s.slug) &&
        (s.enabled || s.everPublished);
  }

  void schedule() {
    if (!_shouldPublish) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), publishNow);
  }

  Future<void> publishNow() async {
    _debounce?.cancel();
    if (!_shouldPublish) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    state = state.copyWith(publishing: true);
    try {
      await _publish(retryMissing: true);
      if (!mounted) return;
      state = state.copyWith(
        publishing: false,
        publishedAt: DateTime.now(),
        error: null,
        slugTaken: false,
      );
      if (!_settings.everPublished) {
        _ref
            .read(storefrontSettingsProvider.notifier)
            .update((s) => s.copyWith(everPublished: true));
      }
      _startPolling();
      unawaited(pullInbox());
    } on StorefrontApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        publishing: false,
        error: e.message,
        slugTaken: e.status == 409,
      );
    } finally {
      _running = false;
    }
    if (_dirty && mounted) {
      _dirty = false;
      schedule();
    }
  }

  Future<void> _publish({required bool retryMissing}) async {
    final key = await _ref.read(storefrontShopKeyProvider.future);
    final sent = <String>{};
    final payload = _payload(sent);
    final result = await _api.publish(key, payload);
    _uploaded.addAll(sent);
    if (result.missingPhotos.isNotEmpty) {
      _uploaded.removeAll(result.missingPhotos);
      if (retryMissing) await _publish(retryMissing: false);
    }
  }

  Map<String, dynamic> _payload(Set<String> sent) {
    final s = _settings;
    final currency = _ref.read(currencySettingsProvider);
    final business = _ref.read(authProvider).businessName ?? '';
    final products = _ref
        .read(mockProductsProvider)
        .where((p) => p.active && p.showOnStorefront)
        .toList();
    return {
      'slug': s.slug,
      'name': s.displayName.trim().isNotEmpty
          ? s.displayName.trim()
          : (business.trim().isNotEmpty ? business.trim() : 'Boutique'),
      'usd_rate': currency.isLocalUsd ? 0 : currency.usdToLocalRate,
      'settings': {
        'enabled': s.enabled,
        'paused': s.paused,
        'accept_when_closed': s.acceptWhenClosed,
        'open_hour': s.openHour,
        'close_hour': s.closeHour,
        'closed_weekdays': s.closedWeekdays.toList()..sort(),
        'description': s.description,
        'pickup_note': s.pickupNote,
        'cover': _photoRef(s.coverDataUrl, sent),
      },
      'products': [
        for (final p in products)
          {
            'id': '${p.id}',
            'name': p.name,
            'category': p.category,
            'description': p.description,
            'price_htg': double.parse(p.sellingPriceHtg.toStringAsFixed(2)),
            'regular_price_htg': p.discountPercent > 0 ? p.priceHtg : 0,
            'photo': _photoRef(p.photoDataUrl, sent),
            'track_stock': p.trackStock,
            'stock': p.stockQuantity,
            'unit': p.stockUnit == 'u' ? '' : p.stockUnit,
            'options': [
              for (final g in p.options)
                {
                  'id': g.id,
                  'name': g.name,
                  'required': g.required,
                  'multiple': g.multiple,
                  'choices': [
                    for (final c in g.choices)
                      {'id': c.id, 'name': c.name, 'delta_htg': c.priceDeltaHtg},
                  ],
                },
            ],
          },
      ],
    };
  }

  /// Server path when the photo was already sent this session, else the data URL.
  String _photoRef(String? dataUrl, Set<String> sent) {
    if (dataUrl == null || dataUrl.isEmpty) return '';
    final match = RegExp(r'^data:image/(png|jpeg|jpg|webp);base64,(.+)$')
        .firstMatch(dataUrl);
    if (match == null) return '';
    final List<int> bytes;
    try {
      bytes = base64Decode(match.group(2)!);
    } catch (_) {
      return '';
    }
    final ext = switch (match.group(1)) { 'png' => 'png', 'webp' => 'webp', _ => 'jpg' };
    final path =
        '/storefront/photos/${sha256.convert(bytes).toString().substring(0, 32)}.$ext';
    if (_uploaded.contains(path)) return path;
    sent.add(path);
    return dataUrl;
  }

  void _startPolling() {
    _poll ??= Timer.periodic(pollEvery, (_) => pullInbox());
  }

  Future<void> pullInbox() async {
    final s = _settings;
    if (!s.loaded || !s.everPublished) return;
    try {
      final key = await _ref.read(storefrontShopKeyProvider.future);
      final rows = await _api.inbox(key);
      if (!mounted) return;
      importRequests(rows, notify: !_firstPull);
      _firstPull = false;
      state = state.copyWith(
        inboxAt: DateTime.now(),
        openQuotes: rows.where((r) => r.isQuote && !r.isPaid).length,
        paidOrders: rows.where((r) => r.isPaid).length,
      );
    } on StorefrontApiException {
      // Next poll retries; publish errors are what the vitrine screen shows.
    }
  }

  /// Adds new devis to Devis and paid requests to Commandes, once each.
  void importRequests(List<StorefrontInboxRequest> rows, {bool notify = true}) {
    final products = {for (final p in _ref.read(mockProductsProvider)) p.id: p};
    final rate = _ref.read(currencySettingsProvider).usdToLocalRate;
    String? newOrder;
    String? newQuote;
    for (final request in rows.reversed) {
      final quoteId =
          request.fromRegister ? request.externalRef : 'vit_${request.id}';
      final quotes = _ref.read(quotesProvider);
      var quote = quotes.where((q) => q.id == quoteId).firstOrNull;

      if (request.isQuote && !request.fromRegister && quote == null) {
        quote = MockRetailQuote(
          id: quoteId,
          quoteNumber: request.number,
          checkoutId: request.id,
          lines: [
            for (final line in request.lines)
              MockQuoteLine(
                product: _productFor(line, products, rate),
                quantity: line.quantity,
                unitPriceHtg: line.unitHtg,
              ),
          ],
          clientName: request.customerName,
          clientPhone: request.customerPhone,
          clientEmail:
              request.customerEmail.isEmpty ? null : request.customerEmail,
          fulfillmentMode: RetailFulfillmentMode.pickup,
          paymentLinkSent: true,
          createdAt: request.createdAt,
        );
        _ref.read(quotesProvider.notifier).add(quote);
        newQuote ??= request.number;
      }

      if (!request.isPaid) continue;
      final orderId = 'vit_${request.id}';
      if (_ref.read(retailOrdersProvider).any((o) => o.id == orderId)) {
        continue;
      }
      if (quote != null && quote.status == MockRetailQuoteStatus.draft) {
        _ref.read(quotesProvider.notifier)
          ..markQuotePaid(quote.id)
          ..convertToOrder(quote.id);
      }
      final subtotal =
          request.lines.fold<double>(0, (s, l) => s + l.unitHtg * l.quantity);
      _ref.read(retailOrdersProvider.notifier).add(
            RetailOrder(
              id: orderId,
              orderNumber: request.number,
              fromQuoteId: quote?.id,
              clientName: request.customerName,
              clientPhone: request.customerPhone,
              clientEmail:
                  request.customerEmail.isEmpty ? null : request.customerEmail,
              fulfillmentMode: RetailFulfillmentMode.pickup,
              status: RetailOrderStatus.paid,
              paymentSource: RetailPaymentSource.storefront,
              paymentMethod: request.paymentMethod == 'moncash'
                  ? PaymentMethodType.moncash
                  : PaymentMethodType.card,
              lines: [
                for (final line in request.lines)
                  RetailOrderLine(
                    productName: line.displayName,
                    productId: int.tryParse(line.productId) ?? 0,
                    quantity: line.quantity,
                    unitPriceHtg: line.unitHtg,
                  ),
              ],
              discountPercent: subtotal > 0 && request.discountHtg > 0
                  ? request.discountHtg / subtotal * 100
                  : 0,
              createdAt: request.createdAt,
              paidAt: request.paidAt ?? DateTime.now(),
            ),
          );
      final sold = <int, int>{};
      for (final line in request.lines) {
        final id = int.tryParse(line.productId);
        if (id != null && products.containsKey(id)) {
          sold[id] = (sold[id] ?? 0) + line.quantity;
        }
      }
      if (sold.isNotEmpty) {
        _ref.read(mockProductsProvider.notifier).applySale(sold);
      }
      newOrder ??= request.number;
    }
    if (!notify) return;
    final notifications = _ref.read(appNotificationProvider.notifier);
    if (newOrder != null) {
      notifications.show('Commande en ligne payée : $newOrder');
    } else if (newQuote != null) {
      notifications.show(
        'Nouveau devis reçu de la vitrine : $newQuote',
        kind: AppNotificationKind.info,
      );
    }
  }

  MockProduct _productFor(
    StorefrontInboxLine line,
    Map<int, MockProduct> products,
    double rate,
  ) {
    final known = products[int.tryParse(line.productId)];
    if (known != null) {
      return line.optionsLabel.isEmpty
          ? known
          : known.copyWith(name: line.displayName);
    }
    return MockProduct(
      id: int.tryParse(line.productId) ?? 0,
      name: line.displayName,
      category: 'Vitrine',
      priceHtg: line.unitHtg,
      priceUsd: rate > 0 ? line.unitHtg / rate : 0,
      costHtg: 0,
      stockQuantity: 0,
      minStock: 0,
      trackStock: false,
    );
  }

  /// Pay link for a devis made at the register. Anyone with it can pay.
  Future<String> shareQuote(MockRetailQuote quote) async {
    if (!_settings.everPublished || !isValidStorefrontSlug(_settings.slug)) {
      throw StorefrontApiException(
        'Activez la vitrine dans Vitrine en ligne pour partager un lien de paiement.',
      );
    }
    final key = await _ref.read(storefrontShopKeyProvider.future);
    final id = await _api.shareRequest(key, {
      'kind': 'devis',
      'reference': quote.id,
      'number': quote.quoteNumber,
      'discount_htg':
          double.parse(quote.discountAmountHtg().toStringAsFixed(2)),
      'customer': {
        'name': quote.clientName ?? '',
        'phone': quote.clientPhone ?? '',
        'email': quote.clientEmail ?? '',
      },
      'lines': [
        for (final line in quote.lines)
          {
            'product_id': '${line.product.id}',
            'name': line.product.name,
            'quantity': line.quantity,
            'unit_htg': double.parse(line.unitPriceHtg.toStringAsFixed(2)),
          },
      ],
    });
    _ref.read(quotesProvider.notifier).markPaymentLinkSent(quote.id);
    _startPolling();
    return StorefrontLinks.request(id);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }
}

final storefrontSyncProvider =
    StateNotifierProvider<StorefrontSyncNotifier, StorefrontSyncState>((ref) {
  final notifier = StorefrontSyncNotifier(ref);
  ref.listen(storefrontSettingsProvider, (_, _) => notifier.schedule());
  ref.listen(mockProductsProvider, (_, _) => notifier.schedule());
  ref.listen(currencySettingsProvider, (_, _) => notifier.schedule());
  Future<void>.microtask(notifier.schedule);
  return notifier;
});

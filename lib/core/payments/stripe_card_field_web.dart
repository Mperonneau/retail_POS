import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'payments_client.dart';
import 'stripe_card_controller.dart';

Future<void>? _stripeJsLoad;

/// Loads Stripe.js once. The publishable key is applied later, per field.
Future<void> _ensureStripeJs() {
  if (_stripeFunction() != null) return Future<void>.value();
  return _stripeJsLoad ??= _injectStripeJs();
}

Future<void> _injectStripeJs() async {
  const src = 'https://js.stripe.com/v3/';
  if (web.document.querySelector('script[src="$src"]') == null) {
    final script = web.HTMLScriptElement()
      ..src = src
      ..async = true;
    web.document.head?.append(script);
  }
  for (var i = 0; i < 50; i++) {
    if (_stripeFunction() != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  _stripeJsLoad = null;
  throw PaymentsException('Stripe.js n\'a pas pu être chargé.');
}

JSFunction? _stripeFunction() {
  final raw = web.window.getProperty<JSAny?>('Stripe'.toJS);
  if (raw == null || raw.isUndefinedOrNull) return null;
  return raw.isA<JSFunction>() ? raw as JSFunction : null;
}

extension type _StripeJs(JSObject _) implements JSObject {
  external JSObject elements();
  external JSPromise<JSObject> confirmCardPayment(
    JSString clientSecret,
    JSObject data,
  );
}

extension type _StripeElements(JSObject _) implements JSObject {
  external JSObject create(JSString type, JSAny? options);
}

extension type _StripeElement(JSObject _) implements JSObject {
  external void mount(JSObject target);
  external void destroy();
}

String _frenchCardError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('incomplete')) {
    return 'Les informations de la carte sont incomplètes.';
  }
  if (lower.contains('declined')) return 'La carte a été refusée.';
  if (lower.contains('expired')) return 'La carte est expirée.';
  if (lower.contains('security code') || lower.contains('cvc')) {
    return 'Le code de sécurité est invalide.';
  }
  if (lower.contains('insufficient')) return 'Fonds insuffisants.';
  if (message.trim().isEmpty) return 'La carte a été refusée.';
  return message;
}

/// Stripe Card Element mounted in the page. Card data stays in Stripe.js.
class StripeCardField extends StatefulWidget {
  const StripeCardField({
    super.key,
    required this.publishableKey,
    required this.controller,
    required this.isDark,
    this.onReady,
    this.onError,
  });

  final String publishableKey;
  final StripeCardController controller;
  final bool isDark;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;

  @override
  State<StripeCardField> createState() => _StripeCardFieldState();
}

class _StripeCardFieldState extends State<StripeCardField> {
  _StripeElement? _card;
  var _reportedReady = false;

  @override
  void dispose() {
    widget.controller.detach();
    final card = _card;
    _card = null;
    if (card != null) {
      try {
        card.destroy();
      } catch (_) {}
    }
    super.dispose();
  }

  void _onElementCreated(Object raw) {
    final element = raw as web.HTMLElement;
    final style = element.style;
    style.width = '100%';
    style.height = '44px';
    style.maxHeight = '44px';
    style.boxSizing = 'border-box';
    style.padding = '12px';
    style.overflow = 'hidden';
    style.border = widget.isDark ? '1px solid #3A3A3A' : '1px solid #E0E0E0';
    style.borderRadius = '8px';
    style.backgroundColor = widget.isDark ? '#1C1C1C' : '#FFFFFF';
    unawaited(_mount(element));
  }

  Future<void> _mount(web.HTMLElement element) async {
    try {
      await _ensureStripeJs();
      if (!mounted) return;
      for (var i = 0; i < 20 && !element.isConnected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
      final ctor = _stripeFunction();
      if (ctor == null) {
        throw PaymentsException('Stripe.js n\'a pas pu être chargé.');
      }
      final stripe = _StripeJs(
        ctor.callAsConstructor<JSObject>(widget.publishableKey.toJS),
      );
      final options = <String, Object?>{
        'hidePostalCode': true,
        'disableLink': true,
        'style': {
          'base': {
            'fontSize': '16px',
            'color': widget.isDark ? '#F7F5F2' : '#1A1A1A',
            'fontFamily': 'system-ui, sans-serif',
            '::placeholder': {'color': '#9A9A9A'},
          },
          'invalid': {'color': '#C62828'},
        },
      }.jsify();
      final card = _StripeElement(
        _StripeElements(stripe.elements()).create('card'.toJS, options),
      );
      card.mount(element);
      _card = card;
      widget.controller.attach(
        (clientSecret) => _confirm(stripe, card, clientSecret),
      );
      if (mounted && !_reportedReady) {
        _reportedReady = true;
        widget.onReady?.call();
      }
    } on PaymentsException catch (e) {
      widget.onError?.call(e.message);
    } catch (_) {
      widget.onError?.call('Le formulaire carte n\'a pas pu s\'afficher.');
    }
  }

  Future<void> _confirm(
    _StripeJs stripe,
    _StripeElement card,
    String clientSecret,
  ) async {
    final paymentMethod = JSObject();
    paymentMethod.setProperty('card'.toJS, card);
    final data = JSObject();
    data.setProperty('payment_method'.toJS, paymentMethod);
    data.setProperty('return_url'.toJS, web.window.location.href.toJS);
    final JSObject result;
    try {
      result = await stripe
          .confirmCardPayment(clientSecret.toJS, data)
          .toDart;
    } catch (_) {
      throw PaymentsException('Le paiement par carte a échoué.');
    }
    final error = result.getProperty<JSAny?>('error'.toJS);
    if (error != null && !error.isUndefinedOrNull) {
      final message = (error as JSObject).getProperty<JSString?>('message'.toJS);
      throw PaymentsException(_frenchCardError(message?.toDart ?? ''));
    }
    final intent = result.getProperty<JSAny?>('paymentIntent'.toJS);
    var status = '';
    if (intent != null && !intent.isUndefinedOrNull) {
      status =
          (intent as JSObject).getProperty<JSString?>('status'.toJS)?.toDart ??
          '';
    }
    if (status != 'succeeded') {
      throw PaymentsException('Le paiement n\'est pas confirmé.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _onElementCreated,
    );
  }
}

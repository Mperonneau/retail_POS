import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../money.dart';
import '../widgets.dart';
import 'pay_sheet.dart';
import 'receipt_view.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key, required this.requestId});

  final String requestId;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final _api = StorefrontApi();
  final _receiptKey = GlobalKey();
  Uint8List? _receiptPng;
  RequestView? _request;
  String? _error;
  bool _notFound = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Someone else may pay this link; pick that up while the page is open.
    _refresh = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_request != null && !_request!.isPaid) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final request = await _api.request(widget.requestId);
      if (!mounted) return;
      web.document.title =
          '${request.isQuote ? 'Devis' : 'Commande'} ${request.number}';
      setState(() => _request = request);
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureReceipt());
    } on ApiException catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = e.message;
        _notFound = e.status == 404;
      });
    }
  }

  String get _link => web.window.location.href;

  /// Leaves the receipt and opens this company's vitrine.
  void _close() {
    final slug = _request?.shopSlug.trim() ?? '';
    context.go(slug.isEmpty ? '/' : '/$slug');
  }

  Future<void> _pay() async {
    final paid = await showPaySheet(context, api: _api, request: _request!);
    if (paid != null && mounted) {
      setState(() => _request = paid);
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureReceipt());
    }
  }

  String _shareText(RequestView request) {
    final items = request.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity,
    );
    final noun = items > 1 ? 'articles' : 'article';
    final kind = request.isQuote ? 'Devis' : 'Commande';
    return '$kind ${request.number} · ${request.shopName}\n'
        '$items $noun · ${Money.usd(request.orderUsdCents)}\n'
        '$_link';
  }

  Future<void> _captureReceipt() async {
    final boundary =
        _receiptKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !mounted) return;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      _receiptPng = data.buffer.asUint8List();
    } catch (_) {
      _receiptPng = null;
    }
  }

  /// Starts the system share sheet in the tap itself, with the picture already ready.
  void _share() {
    final request = _request;
    if (request == null) return;
    final text = _shareText(request);
    final subject = '${request.isQuote ? 'Devis' : 'Reçu'} ${request.number}';
    final bytes = _receiptPng;
    if (bytes != null && _shareImage(bytes, text, subject, request.number)) {
      return;
    }
    Share.share(text, subject: subject);
  }

  bool _shareImage(
    Uint8List bytes,
    String text,
    String subject,
    String number,
  ) {
    try {
      final file = web.File(
        [bytes.buffer.toJS].toJS,
        'recu-$number.png',
        web.FilePropertyBag()..type = 'image/png',
      );
      final data = web.ShareData(
        files: [file].toJS,
        text: text,
        title: subject,
      );
      final navigator = web.window.navigator;
      if (!navigator.canShare(data)) return false;
      navigator.share(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) {
      return Scaffold(
        body: _error == null
            ? const LoadingView()
            : MessageView(
                icon: _notFound
                    ? Icons.link_off_rounded
                    : Icons.wifi_off_rounded,
                title: _notFound ? 'Lien introuvable' : 'Chargement impossible',
                message: _error!,
                actionLabel: _notFound ? null : 'Réessayer',
                onAction: _notFound ? null : _load,
              ),
      );
    }
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 140),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kPhoneMaxWidth),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppCloseButton(
                        key: const Key('receipt-close'),
                        onPressed: _close,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RepaintBoundary(
                      key: _receiptKey,
                      child: OrderReceipt(request: request, link: _link),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kPhoneMaxWidth),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.warmOffWhite,
                border: Border(top: BorderSide(color: Color(0xFFECEAE4))),
              ),
              child: request.isPaid
                  ? Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Fermer',
                            icon: Icons.close_rounded,
                            variant: AppButtonVariant.secondary,
                            onPressed: _close,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: AppButton(
                            label: 'Partager',
                            icon: Icons.ios_share_rounded,
                            onPressed: () => _share(),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Partager',
                            icon: Icons.ios_share_rounded,
                            variant: AppButtonVariant.secondary,
                            onPressed: () => _share(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: AppButton(
                            label: 'Payer ${Money.usd(request.orderUsdCents)}',
                            icon: Icons.lock_outline_rounded,
                            onPressed: _pay,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../money.dart';
import '../widgets.dart';
import 'pay_sheet.dart';
import 'product_sheet.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key, required this.requestId});

  final String requestId;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final _api = StorefrontApi();
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
      web.document.title = '${request.isQuote ? 'Devis' : 'Commande'} ${request.number}';
      setState(() => _request = request);
    } on ApiException catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = e.message;
        _notFound = e.status == 404;
      });
    }
  }

  String get _link => web.window.location.href;

  Future<void> _pay() async {
    final paid = await showPaySheet(context, api: _api, request: _request!);
    if (paid != null && mounted) setState(() => _request = paid);
  }

  void _share() {
    showStoreSheet(context, (_) => _ShareSheet(request: _request!, link: _link));
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) {
      return Scaffold(
        body: _error == null
            ? const LoadingView()
            : MessageView(
                icon: _notFound ? Icons.link_off_rounded : Icons.wifi_off_rounded,
                title: _notFound ? 'Lien introuvable' : 'Chargement impossible',
                message: _error!,
                actionLabel: _notFound ? null : 'Réessayer',
                onAction: _notFound ? null : _load,
              ),
      );
    }
    final rate = request.usdRate;
    final kindLabel = request.isQuote ? 'Devis' : 'Commande';
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ShopHeader(request: request),
                    const SizedBox(height: 16),
                    if (request.isPaid) ...[
                      _PaidHero(request: request),
                      const SizedBox(height: 16),
                    ],
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$kindLabel ${request.number}',
                                        style: AppTextStyles.h2(color: AppColors.nearBlack)),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        DateFormat('d MMM yyyy à HH:mm', 'fr').format(request.createdAt),
                                        if (request.customerName.isNotEmpty) request.customerName,
                                      ].join(' · '),
                                      style: AppTextStyles.caption(),
                                    ),
                                  ],
                                ),
                              ),
                              request.isPaid
                                  ? const Pill(label: 'Payé', color: AppColors.deepGreen)
                                  : const Pill(label: 'À payer', color: AppColors.amber),
                            ],
                          ),
                          const Divider(height: 28, color: Color(0xFFF0EEE9)),
                          for (final line in request.lines) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 32,
                                  child: Text('${line.quantity}×',
                                      style: AppTextStyles.body(color: AppColors.darkGray)
                                          .copyWith(fontWeight: FontWeight.w600)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(line.name,
                                          style: AppTextStyles.body(color: AppColors.nearBlack)
                                              .copyWith(fontWeight: FontWeight.w600)),
                                      if (line.optionsLabel.isNotEmpty)
                                        Text(line.optionsLabel, style: AppTextStyles.caption()),
                                    ],
                                  ),
                                ),
                                DualPrice(htg: line.totalHtg, rate: rate, alignEnd: true),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (request.discountHtg > 0) ...[
                            Row(
                              children: [
                                Expanded(child: Text('Remise', style: AppTextStyles.body())),
                                Text('- ${Money.usdFromHtg(request.discountHtg, rate)}',
                                    style: AppTextStyles.body(color: AppColors.deepGreen)
                                        .copyWith(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Divider(height: 8, color: Color(0xFFF0EEE9)),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text('Total',
                                    style: AppTextStyles.h2(color: AppColors.nearBlack)),
                              ),
                              DualPrice(htg: request.totalHtg, rate: rate, large: true, alignEnd: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (request.note.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Panel(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.edit_note_rounded, size: 20, color: AppColors.darkGray),
                            const SizedBox(width: 10),
                            Expanded(child: Text(request.note, style: AppTextStyles.body())),
                          ],
                        ),
                      ),
                    ],
                    if (!request.isPaid) ...[
                      const SizedBox(height: 12),
                      _Hint(
                        icon: request.isQuote ? Icons.mark_email_read_outlined : Icons.groups_outlined,
                        text: request.isQuote
                            ? 'La boutique a reçu ce devis. Payez-le pour le transformer en commande, '
                                'ou partagez le lien à la personne qui paiera.'
                            : 'Payez maintenant, ou partagez ce lien : n\'importe qui peut l\'ouvrir et payer, '
                                'en Haïti comme à l\'étranger.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: request.isPaid
          ? null
          : SafeArea(
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
                    child: Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Partager',
                            icon: Icons.ios_share_rounded,
                            variant: AppButtonVariant.secondary,
                            onPressed: _share,
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

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.request});

  final RequestView request;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: request.shopSlug.isEmpty ? null : () => context.go('/${request.shopSlug}'),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ProductPhoto(url: request.coverUrl, name: request.shopName, radius: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.shopName,
                      style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 17)),
                  if (request.shopSlug.isNotEmpty)
                    Text('Voir la boutique',
                        style: AppTextStyles.caption(color: AppColors.primaryBlue)
                            .copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidHero extends StatelessWidget {
  const _PaidHero({required this.request});

  final RequestView request;

  @override
  Widget build(BuildContext context) {
    final method = switch (request.paymentMethod) {
      'card' => 'par carte',
      'moncash' => 'par MonCash',
      _ => '',
    };
    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.deepGreen, size: 34),
          ),
          const SizedBox(height: 12),
          Text('Paiement reçu',
              style: AppTextStyles.h1(color: AppColors.nearBlack).copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            'Commande ${request.number} confirmée${method.isEmpty ? '' : ', payée $method'}.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(color: AppColors.darkGray).copyWith(fontSize: 14),
          ),
          if (request.pickupNote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.storefront_outlined, size: 20, color: AppColors.primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Retrait',
                            style: AppTextStyles.body(color: AppColors.primaryBlue)
                                .copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(request.pickupNote,
                            style: AppTextStyles.body(color: AppColors.nearBlack)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: AppTextStyles.body(color: AppColors.nearBlack).copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.request, required this.link});

  final RequestView request;
  final String link;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _copied = false;

  String get _message {
    final r = widget.request;
    final what = r.isQuote ? 'le devis' : 'la commande';
    return 'Bonjour, peux-tu payer $what ${r.number} chez ${r.shopName} '
        '(${Money.usd(r.orderUsdCents)}) ? Paiement par carte ou MonCash : ${widget.link}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Partager pour paiement',
                      style: AppTextStyles.h1(color: AppColors.nearBlack).copyWith(fontSize: 20)),
                ),
                AppCloseButton(onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'La personne qui reçoit ce lien voit le détail et paie par carte (en dollars) ou MonCash (en gourdes).',
              style: AppTextStyles.body(color: AppColors.darkGray),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6E3DC)),
                ),
                child: QrImageView(data: widget.link, size: 180, backgroundColor: AppColors.white),
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Envoyer le lien',
              icon: Icons.send_rounded,
              onPressed: () => Share.share(_message, subject: 'Paiement ${widget.request.number}'),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: _copied ? 'Lien copié' : 'Copier le lien',
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.link));
                if (mounted) setState(() => _copied = true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

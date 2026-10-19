import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retail_pos/core/payments/open_payment_url.dart';
import 'package:retail_pos/core/payments/payments_client.dart';
import 'package:retail_pos/core/payments/stripe_card_field.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';

import '../api.dart';
import '../money.dart';
import 'product_sheet.dart';

enum PayMethod { card, moncash }

/// Returns the paid request once Stripe or MonCash has confirmed it.
Future<RequestView?> showPaySheet(
  BuildContext context, {
  required StorefrontApi api,
  required RequestView request,
}) {
  return showStoreSheet<RequestView>(
    context,
    (_) => _PaySheet(api: api, request: request),
  );
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.api, required this.request});

  final StorefrontApi api;
  final RequestView request;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  PayMethod? _method;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_method != null)
                    IconButton(
                      onPressed: () => setState(() => _method = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Changer de moyen de paiement',
                    ),
                  Expanded(
                    child: Text(
                      switch (_method) {
                        null => 'Payer ${widget.request.number}',
                        PayMethod.card => 'Paiement par carte',
                        PayMethod.moncash => 'Paiement MonCash',
                      },
                      style: AppTextStyles.h1(color: AppColors.nearBlack).copyWith(fontSize: 20),
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 14),
              switch (_method) {
                null => _MethodPicker(
                    request: widget.request,
                    onPick: (m) => setState(() => _method = m),
                  ),
                PayMethod.card => _CardPay(api: widget.api, request: widget.request),
                PayMethod.moncash => _MoncashPay(api: widget.api, request: widget.request),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.request, required this.onPick});

  final RequestView request;
  final ValueChanged<PayMethod> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MethodTile(
          icon: Icons.credit_card_rounded,
          color: AppColors.primaryBlue,
          title: 'Carte',
          subtitle: 'Visa, Mastercard… Facturé en dollars US, frais inclus.',
          trailing: Money.usd(request.orderUsdCents),
          onTap: () => onPick(PayMethod.card),
        ),
        const SizedBox(height: 10),
        _MethodTile(
          icon: Icons.phone_iphone_rounded,
          color: const Color(0xFFE4002B),
          title: 'MonCash',
          subtitle: 'Facturé en gourdes, depuis votre compte MonCash.',
          trailing: Money.htg(request.moncashHtg.toDouble()),
          onTap: () => onPick(PayMethod.moncash),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.darkGray),
            const SizedBox(width: 6),
            Text('Paiement sécurisé. La boutique ne voit pas votre carte.',
                style: AppTextStyles.caption()),
          ],
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE6E3DC)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTextStyles.body(color: AppColors.nearBlack)
                            .copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(subtitle, style: AppTextStyles.caption()),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(trailing,
                  style: AppTextStyles.body(color: AppColors.nearBlack)
                      .copyWith(fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded, color: AppColors.darkGray),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppTextStyles.price(color: AppColors.nearBlack).copyWith(fontSize: 18)
        : AppTextStyles.body(color: AppColors.darkGray).copyWith(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warmOffWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(message, style: AppTextStyles.errorText().copyWith(fontSize: 13)),
      );
}

/// Bill in USD only: order, one « Frais » line, total. Card data stays in Stripe.js.
class _CardPay extends StatefulWidget {
  const _CardPay({required this.api, required this.request});

  final StorefrontApi api;
  final RequestView request;

  @override
  State<_CardPay> createState() => _CardPayState();
}

class _CardPayState extends State<_CardPay> {
  final _controller = StripeCardController();
  CardIntent? _intent;
  String? _error;
  bool _ready = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final intent = await widget.api.startCard(widget.request.id);
      if (!mounted) return;
      if (intent.publishableKey.isEmpty || intent.clientSecret.isEmpty) {
        setState(() => _error = 'Le paiement par carte n\'est pas disponible pour le moment.');
        return;
      }
      setState(() => _intent = intent);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pay() async {
    final intent = _intent;
    if (intent == null) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      await _controller.confirmPayment(intent.clientSecret);
      final paid = await widget.api.confirmCard(widget.request.id, intent.id);
      if (!mounted) return;
      Navigator.of(context).pop(paid);
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = _intent;
    final pricing = intent?.pricing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bill(children: [
          _BillRow(
            widget.request.isQuote ? 'Devis' : 'Commande',
            Money.usd(pricing?.orderUsdCents ?? widget.request.orderUsdCents),
          ),
          _BillRow('Frais', pricing == null ? '…' : Money.usd(pricing.combinedFeeUsdCents)),
          const Divider(height: 14),
          _BillRow('Total', pricing == null ? '…' : Money.usd(pricing.totalUsdCents), bold: true),
        ]),
        const SizedBox(height: 16),
        if (intent != null) ...[
          Text('Carte bancaire', style: AppTextStyles.inputLabel()),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: StripeCardField(
              publishableKey: intent.publishableKey,
              controller: _controller,
              isDark: false,
              onReady: () => setState(() => _ready = true),
              onError: (m) => setState(() => _error = m),
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Payer ${Money.usd(intent.pricing.totalUsdCents)}',
            icon: Icons.lock_outline_rounded,
            isLoading: _paying,
            onPressed: _ready && !_paying ? _pay : null,
          ),
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          ),
        if (_error != null) _ErrorText(_error!),
        if (_error != null && intent == null) ...[
          const SizedBox(height: 12),
          AppButton(label: 'Réessayer', variant: AppButtonVariant.secondary, onPressed: _start),
        ],
      ],
    );
  }
}

/// Bill in gourdes only. QR for another phone, or Payer opens MonCash here.
class _MoncashPay extends StatefulWidget {
  const _MoncashPay({required this.api, required this.request});

  final StorefrontApi api;
  final RequestView request;

  @override
  State<_MoncashPay> createState() => _MoncashPayState();
}

class _MoncashPayState extends State<_MoncashPay> {
  MoncashStart? _start;
  String? _error;
  Timer? _poll;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    try {
      final start = await widget.api.startMoncash(widget.request.id);
      if (!mounted) return;
      setState(() => _start = start);
      _attempts = 0;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _check() async {
    if (++_attempts > 100) {
      _poll?.cancel();
      if (mounted) {
        setState(() => _error = 'Toujours en attente de MonCash. Réessayez quand le paiement est fait.');
      }
      return;
    }
    try {
      final paid = await widget.api.moncashStatus(widget.request.id);
      if (paid != null && mounted) {
        _poll?.cancel();
        Navigator.of(context).pop(paid);
      }
    } on ApiException {
      // Digicel can be slow to list a new payment; keep polling.
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bill(children: [
          for (final line in widget.request.lines)
            _BillRow('${line.quantity} × ${line.name}', Money.htg(line.totalHtg)),
          if (widget.request.discountHtg > 0)
            _BillRow('Remise', '- ${Money.htg(widget.request.discountHtg)}'),
          const Divider(height: 14),
          _BillRow('Total', Money.htg(widget.request.moncashHtg.toDouble()), bold: true),
        ]),
        const SizedBox(height: 16),
        if (start != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6E3DC)),
              ),
              child: QrImageView(data: start.paymentUrl, size: 176, backgroundColor: AppColors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Scannez ce code avec un autre téléphone, ou touchez Payer pour ouvrir MonCash sur celui-ci.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption().copyWith(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Payer ${Money.htg(start.amountHtg.toDouble())}',
            icon: Icons.open_in_new_rounded,
            onPressed: () => openPaymentUrl(start.paymentUrl),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('En attente de la confirmation MonCash…', style: AppTextStyles.caption()),
            ],
          ),
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          ),
        if (_error != null) _ErrorText(_error!),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppButton(
            label: start == null ? 'Réessayer' : 'Vérifier le paiement',
            variant: AppButtonVariant.secondary,
            onPressed: start == null
                ? _create
                : () {
                    setState(() => _error = null);
                    _attempts = 0;
                    _poll?.cancel();
                    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
                  },
          ),
        ],
      ],
    );
  }
}

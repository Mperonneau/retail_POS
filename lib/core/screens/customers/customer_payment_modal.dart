import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../retail/receipt/share_receipt_file.dart';
import '../../models/customer.dart';
import '../../payments/card_charge_pricing.dart';
import '../../payments/open_payment_url.dart';
import '../../payments/payments_client.dart';
import '../../payments/stripe_card_field.dart';
import '../../printing/shop_pdf.dart';
import '../../providers/currency_settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_close_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/card_fee_breakdown.dart';
import '../../widgets/payment_receipt_dialogs.dart';

// ── Payment method enum ────────────────────────────────────────────────────────

enum CustomerPayMethod { cash, moncash, card }

extension _PayMethodX on CustomerPayMethod {
  String get label {
    switch (this) {
      case CustomerPayMethod.cash:
        return 'Espèces';
      case CustomerPayMethod.moncash:
        return 'MonCash';
      case CustomerPayMethod.card:
        return 'Carte';
    }
  }

  IconData get icon {
    switch (this) {
      case CustomerPayMethod.cash:
        return Icons.money_outlined;
      case CustomerPayMethod.moncash:
        return Icons.phone_android_outlined;
      case CustomerPayMethod.card:
        return Icons.credit_card_outlined;
    }
  }

  Color get color {
    switch (this) {
      case CustomerPayMethod.cash:
        return const Color(0xFF059669);
      case CustomerPayMethod.moncash:
        return const Color(0xFF7C3AED);
      case CustomerPayMethod.card:
        return const Color(0xFF2563EB);
    }
  }
}

// ── Receipt number generator (per session counter) ────────────────────────────

int _receiptSeq = 0;
String _nextReceiptNumber() {
  _receiptSeq++;
  return 'PAY-${DateTime.now().year}-${_receiptSeq.toString().padLeft(3, '0')}';
}

// ── Internal result data class ─────────────────────────────────────────────────

class _PaymentResult {
  final String receiptNumber;
  final double amountPaid;
  final double previousBalance;
  final double remainingBalance;
  final CustomerPayMethod method;
  final String? methodDetail;
  final DateTime paidAt;

  _PaymentResult({
    required this.receiptNumber,
    required this.amountPaid,
    required this.previousBalance,
    required this.remainingBalance,
    required this.method,
    this.methodDetail,
    required this.paidAt,
  });
}

enum _CardEntry { form, link }

/// Opens the account payment on the right. A phone uses the full screen.
/// After a payment is recorded, the receipt opens in its own right panel.
Future<void> showCustomerAccountPayment(
  BuildContext context, {
  required Customer customer,
  required double balance,
  required bool isDark,
}) async {
  final result = await _showSidePanel<_PaymentResult>(
    context,
    label: 'Paiement de compte',
    isDark: isDark,
    panel: CustomerPaymentModal(
      customer: customer,
      balance: balance,
      isDark: isDark,
    ),
  );
  if (result == null || !context.mounted) return;
  await _showSidePanel<void>(
    context,
    label: 'Reçu',
    isDark: isDark,
    panel: _AccountReceiptView(
      customer: customer,
      result: result,
      isDark: isDark,
    ),
  );
}

Future<T?> _showSidePanel<T>(
  BuildContext context, {
  required String label,
  required bool isDark,
  required Widget panel,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) {
      final width = MediaQuery.sizeOf(ctx).width;
      final panelWidth = AppConstants.sidePanelWidth(width, 480);
      final bg = isDark ? AppColors.darkSurface : AppColors.white;
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: bg,
          elevation: 12,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: SafeArea(child: panel),
          ),
        ),
      );
    },
  );
}

// ── CustomerPaymentModal ───────────────────────────────────────────────────────

class CustomerPaymentModal extends ConsumerStatefulWidget {
  final Customer customer;
  final double balance;
  final bool isDark;

  const CustomerPaymentModal({
    super.key,
    required this.customer,
    required this.balance,
    required this.isDark,
  });

  @override
  ConsumerState<CustomerPaymentModal> createState() =>
      _CustomerPaymentModalState();
}

class _CustomerPaymentModalState extends ConsumerState<CustomerPaymentModal> {
  CustomerPayMethod _method = CustomerPayMethod.cash;
  _CardEntry _cardEntry = _CardEntry.form;
  bool _recorded = false;

  final _amtCtrl = TextEditingController();
  final _payerNameCtrl = TextEditingController();
  final _payerContactCtrl = TextEditingController();
  final PaymentsClient _payments = PaymentsClient();
  final StripeCardController _cardController = StripeCardController();
  Timer? _poll;

  bool _remoteBusy = false;
  String? _remoteError;
  bool _cardPaid = false;
  bool _moncashPaid = false;
  String? _moncashUrl;
  String? _moncashOrderId;
  int? _moncashAmountHtg;
  int _moncashGeneration = 0;
  bool _cardConfigLoading = false;
  bool _cardConfigLoaded = false;
  String? _publishableKey;
  String? _cardConfigError;
  String? _shareUrl;
  String? _shareSessionId;
  bool _linkCopied = false;

  double get _enteredAmount => double.tryParse(_amtCtrl.text) ?? 0;
  bool get _amountOverBalance => _enteredAmount > widget.balance;
  bool get _amountOk => _enteredAmount > 0 && !_amountOverBalance;
  double get _remainingAfterPayment =>
      _amountOk
          ? (widget.balance - _enteredAmount).clamp(0.0, double.infinity)
          : widget.balance;

  @override
  void initState() {
    super.initState();
    _payerNameCtrl.text = widget.customer.name;
    _payerContactCtrl.text = widget.customer.phone;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cardController.detach();
    _payments.close();
    _amtCtrl.dispose();
    _payerNameCtrl.dispose();
    _payerContactCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged(String v) {
    final next = _enteredAmount.round();
    if (_method == CustomerPayMethod.moncash &&
        _moncashAmountHtg != null &&
        next != _moncashAmountHtg) {
      _poll?.cancel();
      _moncashGeneration++;
      _moncashUrl = null;
      _moncashOrderId = null;
      _moncashPaid = false;
      _moncashAmountHtg = null;
      _remoteBusy = false;
    }
    setState(() {});
  }

  void _record(CustomerPayMethod method, {String? detail}) {
    if (_recorded || !_amountOk) return;
    _recorded = true;
    _poll?.cancel();
    final amount = _enteredAmount;
    final receiptNumber = _nextReceiptNumber();
    final result = _PaymentResult(
      receiptNumber: receiptNumber,
      amountPaid: amount,
      previousBalance: widget.balance,
      remainingBalance: (widget.balance - amount).clamp(0.0, double.infinity),
      method: method,
      methodDetail: detail,
      paidAt: DateTime.now(),
    );
    ref.read(customerProvider.notifier).postPayment(
          customerId: widget.customer.id,
          amountHtg: amount,
          cashierName: 'Caissier',
          paymentMethodLabel: method.label,
          receiptNumber: receiptNumber,
        );
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  bool get _canConfirm {
    if (_recorded || _remoteBusy || !_amountOk) return false;
    if (_method == CustomerPayMethod.cash) return true;
    if (_method == CustomerPayMethod.moncash) {
      if (_moncashPaid) return false;
      if ((_moncashUrl ?? '').trim().isNotEmpty) return true;
      return _enteredAmount.round() >= 1;
    }
    if (_method == CustomerPayMethod.card) {
      if (_cardPaid) return false;
      if (_cardPricing() == null) return false;
      if (_cardEntry == _CardEntry.form) return _cardController.isReady;
      if (_shareUrl != null) return false;
      return _payerNameCtrl.text.trim().isNotEmpty &&
          _payerContactCtrl.text.trim().isNotEmpty;
    }
    return false;
  }

  String _confirmLabel(BuildContext context) {
    if (_remoteBusy) return 'Traitement…';
    if (_method == CustomerPayMethod.card && !_cardPaid) {
      if (_cardEntry == _CardEntry.link) {
        return _shareUrl == null ? 'Créer le lien' : 'En attente du paiement…';
      }
      final pricing = _cardPricing();
      if (pricing == null) return 'Payer par carte';
      return 'Payer ${CurrencyFormatter.usd(pricing.totalUsd)}';
    }
    if (_method == CustomerPayMethod.moncash && !_moncashPaid) {
      return 'Payer ${CurrencyFormatter.local(context, _enteredAmount)}';
    }
    return 'Confirmer le paiement';
  }

  Future<void> _onPay() async {
    if (!_canConfirm) return;
    if (_method == CustomerPayMethod.card && !_cardPaid) {
      if (_cardEntry == _CardEntry.link) {
        await _createShareLink();
      } else {
        await _payByCard();
      }
      return;
    }
    if (_method == CustomerPayMethod.moncash && !_moncashPaid) {
      final url = _moncashUrl?.trim() ?? '';
      if (url.isNotEmpty) {
        openPaymentUrl(url);
        return;
      }
      await _startMoncash();
      return;
    }
    _record(_method);
  }

  CardChargePricing? _cardPricing() {
    final rate = ref.read(currencySettingsProvider).usdToLocalRate;
    final cents = CardChargePricing.htgToUsdCents(_enteredAmount, rate);
    if (cents <= 0) return null;
    return CardChargePricing.fromOrderUsdCents(cents);
  }

  void _selectMethod(CustomerPayMethod method) {
    _poll?.cancel();
    setState(() {
      _method = method;
      _remoteError = null;
    });
    if (method == CustomerPayMethod.card) {
      _loadCardConfig();
      _resumeSharePoll();
    } else if (method == CustomerPayMethod.moncash) {
      if (_moncashPaid) return;
      if ((_moncashUrl ?? '').trim().isNotEmpty) {
        _resumeMoncashPoll();
      } else if (!_remoteBusy && _amountOk) {
        _startMoncash();
      }
    }
  }

  Future<void> _loadCardConfig() async {
    if (_cardConfigLoaded || _cardConfigLoading) return;
    setState(() => _cardConfigLoading = true);
    try {
      final config = await _payments.fetchConfig();
      if (!mounted) return;
      setState(() {
        _cardConfigLoading = false;
        _cardConfigLoaded = true;
        _publishableKey = config.publishableKey;
        if (!config.stripeConfigured) {
          _cardConfigError = 'Stripe n\'est pas configuré sur le serveur.';
        } else if (config.publishableKey.isEmpty) {
          _cardConfigError =
              'Ajoutez STRIPE_PUBLISHABLE_KEY sur le serveur pour saisir la carte ici.';
        } else {
          _cardConfigError = null;
        }
      });
    } on PaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _cardConfigLoading = false;
        _cardConfigError = e.message;
      });
    }
  }

  Future<bool> _intentPaidSoon(String intentId) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (await _payments.cardIntentPaid(intentId)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  String get _paymentReference =>
      'acct-${widget.customer.id}-${_amtCtrl.text.trim()}';

  Future<void> _payByCard() async {
    final pricing = _cardPricing();
    if (pricing == null) {
      setState(
        () => _remoteError =
            'Taux de change indisponible — impossible d\'encaisser en dollars.',
      );
      return;
    }
    _poll?.cancel();
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    try {
      final intent = await _payments.createCardIntent(
        reference: _paymentReference,
        orderUsdCents: pricing.orderUsdCents,
        description: 'Paiement de compte ${widget.customer.name}',
      );
      if (!mounted || _method != CustomerPayMethod.card) {
        if (mounted) setState(() => _remoteBusy = false);
        return;
      }
      await _cardController.confirmPayment(intent.clientSecret);
      final paid = await _intentPaidSoon(intent.id);
      if (!mounted) return;
      if (!paid) {
        setState(() {
          _remoteBusy = false;
          _remoteError = 'Le paiement n\'est pas confirmé.';
        });
        return;
      }
      setState(() {
        _cardPaid = true;
        _remoteBusy = false;
      });
      _record(CustomerPayMethod.card, detail: 'Stripe');
    } on PaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteBusy = false;
        _remoteError = e.message;
      });
    }
  }

  Future<void> _createShareLink() async {
    final pricing = _cardPricing();
    if (pricing == null) {
      setState(
        () => _remoteError =
            'Taux de change indisponible — impossible d\'encaisser en dollars.',
      );
      return;
    }
    final name = _payerNameCtrl.text.trim();
    final contact = _payerContactCtrl.text.trim();
    if (name.isEmpty || contact.isEmpty) return;
    final email = contact.contains('@') ? contact : '';
    _poll?.cancel();
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    try {
      final session = await _payments.createCheckout(
        reference: _paymentReference,
        orderUsdCents: pricing.orderUsdCents,
        description: 'Paiement de compte ${widget.customer.name}',
        recipientName: name,
        recipientEmail: email,
        recipientPhone: email.isEmpty ? contact : '',
      );
      if (!mounted || _method != CustomerPayMethod.card) {
        if (mounted) setState(() => _remoteBusy = false);
        return;
      }
      setState(() {
        _remoteBusy = false;
        _shareUrl = session.url;
        _shareSessionId = session.id;
        _cardEntry = _CardEntry.link;
      });
      _watchShare(session.id);
    } on PaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteBusy = false;
        _remoteError = e.message;
      });
    }
  }

  void _watchShare(String sessionId) {
    _pollPayment(
      () => _payments.checkoutPaid(sessionId),
      onPaid: () async {
        if (!mounted || _cardPaid || _recorded) return;
        setState(() => _cardPaid = true);
        _record(CustomerPayMethod.card, detail: 'Lien de paiement');
      },
    );
  }

  void _resumeSharePoll() {
    final id = _shareSessionId;
    if (id == null || _cardPaid || _method != CustomerPayMethod.card) return;
    _watchShare(id);
  }

  Future<void> _copyShareLink() async {
    final url = _shareUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _linkCopied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  Future<void> _shareLink() async {
    final url = _shareUrl;
    if (url == null || url.isEmpty) return;
    try {
      await Share.share(url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _remoteError = 'Le partage a échoué. Copiez le lien.');
    }
  }

  Future<void> _startMoncash() async {
    final amount = _enteredAmount.round();
    if (amount < 1 || !_amountOk) {
      setState(
        () => _remoteError = 'Le montant MonCash doit être d\'au moins 1 HTG.',
      );
      return;
    }
    _poll?.cancel();
    final generation = ++_moncashGeneration;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
      _moncashAmountHtg = amount;
    });
    try {
      final payment = await _payments.createMoncash(
        orderId: 'acct-${widget.customer.id}-$amount-${DateTime.now().millisecondsSinceEpoch}',
        amountHtg: amount,
      );
      if (!mounted ||
          _method != CustomerPayMethod.moncash ||
          generation != _moncashGeneration) {
        if (mounted && generation == _moncashGeneration) {
          setState(() => _remoteBusy = false);
        }
        return;
      }
      setState(() {
        _remoteBusy = false;
        _moncashUrl = payment.paymentUrl;
        _moncashOrderId = payment.orderId;
      });
      _watchMoncash(payment.orderId);
    } on PaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteBusy = false;
        _remoteError = e.message;
      });
    }
  }

  void _watchMoncash(String orderId) {
    _pollPayment(
      () => _payments.moncashPaid(orderId),
      pendingIsUnpaid: true,
      onPaid: () async {
        if (!mounted || _moncashPaid || _recorded) return;
        setState(() => _moncashPaid = true);
        _record(CustomerPayMethod.moncash, detail: orderId);
      },
    );
  }

  void _resumeMoncashPoll() {
    final id = _moncashOrderId;
    if (id == null || _moncashPaid || _method != CustomerPayMethod.moncash) {
      return;
    }
    _watchMoncash(id);
  }

  bool _moncashStillPending(String message) {
    final lower = message.toLowerCase();
    return lower.contains('transaction not found') ||
        lower.contains('transaction inexistante');
  }

  void _pollPayment(
    Future<bool> Function() check, {
    required Future<void> Function() onPaid,
    bool pendingIsUnpaid = false,
  }) {
    _poll?.cancel();
    var attempts = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (!mounted || attempts > 80) {
        timer.cancel();
        return;
      }
      try {
        final paid = await check();
        if (!paid || !mounted) return;
        timer.cancel();
        await onPaid();
      } on PaymentsException catch (e) {
        if (!mounted) return;
        if (pendingIsUnpaid && _moncashStillPending(e.message)) return;
        timer.cancel();
        setState(() => _remoteError = e.message);
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _buildPaymentStep(
      context,
      widget.isDark,
    );
  }

  // ── Step 0: Payment input ──────────────────────────────────────────────────

  Widget _buildPaymentStep(BuildContext context, bool isDark) {
    final textColor =
        isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final dividerColor =
        (isDark ? AppColors.coolGray : AppColors.darkGray)
            .withValues(alpha: 0.15);
    final amount = _enteredAmount;
    final overBalance = _amountOverBalance;

    return Column(
      key: const ValueKey('payment'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.payments_outlined,
                  size: 16, color: AppColors.amber),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Paiement de compte',
                      style: AppTextStyles.body(color: textColor)
                          .copyWith(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(widget.customer.name,
                      style: AppTextStyles.caption(),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.boldRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.boldRed.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  CurrencyFormatter.local(context, widget.balance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: AppColors.boldRed)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AppCloseButton(onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Divider(height: 1, color: dividerColor),

        Expanded(
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Amount field
              _field(
                controller: _amtCtrl,
                label: 'Montant payé',
                prefixText: 'HTG ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                formatters: InputFormatters.decimalAmount,
                isDark: isDark,
                onChanged: _onAmountChanged,
              ),

              // Error: over balance
              if (overBalance) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.error_outline,
                      size: 13, color: AppColors.boldRed),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Ne peut pas dépasser le solde dû '
                      '(${CurrencyFormatter.local(context, widget.balance)})',
                      style: AppTextStyles.caption(color: AppColors.boldRed),
                    ),
                  ),
                ]),
              ],

              // Live balance-after-payment pill
              if (amount > 0 && !overBalance) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _remainingAfterPayment == 0
                        ? const Color(0xFF059669).withValues(alpha: 0.08)
                        : AppColors.primaryBlue.withValues(alpha: 0.07),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusCard),
                    border: Border.all(
                      color: _remainingAfterPayment == 0
                          ? const Color(0xFF059669).withValues(alpha: 0.2)
                          : AppColors.primaryBlue.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      _remainingAfterPayment == 0
                          ? Icons.check_circle_outline
                          : Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: _remainingAfterPayment == 0
                          ? const Color(0xFF059669)
                          : AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Solde après paiement',
                        style: AppTextStyles.caption(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _remainingAfterPayment == 0
                          ? 'Compte soldé'
                          : CurrencyFormatter.local(
                              context, _remainingAfterPayment),
                      style: AppTextStyles.caption(
                        color: _remainingAfterPayment == 0
                            ? const Color(0xFF059669)
                            : AppColors.primaryBlue,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              // ── Method tabs ──────────────────────────────────────────────
              Text('Moyen de paiement',
                  style: AppTextStyles.caption()
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: CustomerPayMethod.values.map((m) {
                    final selected = _method == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MethodChip(
                        method: m,
                        selected: selected,
                        isDark: isDark,
                        onTap: () => _selectMethod(m),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Method-specific panel ────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildMethodPanel(isDark),
              ),
            ],
          ),
        ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _canConfirm ? _onPay : null,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text(
                _confirmLabel(context),
                style: AppTextStyles.body().copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.nearBlack),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: AppColors.nearBlack,
                disabledBackgroundColor:
                    AppColors.amber.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodPanel(bool isDark) {
    switch (_method) {
      case CustomerPayMethod.cash:
        return _CashPanel(key: const ValueKey('cash'), isDark: isDark);
      case CustomerPayMethod.moncash:
        return _MonCashLive(
          key: const ValueKey('moncash'),
          amountHtg: _enteredAmount,
          amountOk: _amountOk,
          isDark: isDark,
          error: _remoteError,
          preparing: _remoteBusy && (_moncashUrl == null || _moncashUrl!.trim().isEmpty),
          waiting: (_poll?.isActive ?? false) && !_moncashPaid,
          paid: _moncashPaid,
          paymentUrl: _moncashUrl,
        );
      case CustomerPayMethod.card:
        return _CardLive(
          key: const ValueKey('card'),
          isDark: isDark,
          pricing: _cardPricing(),
          orderLocalLabel: CurrencyFormatter.local(context, _enteredAmount),
          error: _remoteError,
          waiting: _remoteBusy || ((_poll?.isActive ?? false) && !_cardPaid),
          paid: _cardPaid,
          entry: _cardEntry,
          entryLocked: _shareUrl != null || _cardPaid || _remoteBusy,
          onEntry: (entry) {
            if (_shareUrl != null || _cardPaid || _remoteBusy) return;
            if (_cardEntry == entry) return;
            setState(() {
              _cardEntry = entry;
              _remoteError = null;
            });
          },
          publishableKey: _publishableKey,
          configLoading: _cardConfigLoading,
          configError: _cardConfigError,
          cardController: _cardController,
          onCardReady: () {
            if (mounted) setState(() {});
          },
          onCardError: (message) {
            if (!mounted) return;
            setState(() => _remoteError = message);
          },
          payerNameCtrl: _payerNameCtrl,
          payerContactCtrl: _payerContactCtrl,
          onPayerChanged: () => setState(() {}),
          shareUrl: _shareUrl,
          linkCopied: _linkCopied,
          onCopyLink: _copyShareLink,
          onShareLink: _shareLink,
        );
    }
  }

  // ── Shared field builder ───────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? prefixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    required bool isDark,
    void Function(String)? onChanged,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      readOnly: readOnly,
      onChanged: onChanged,
      style: AppTextStyles.body().copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption(),
        prefixText: prefixText,
        isDense: true,
        filled: true,
        fillColor:
            isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(
              color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                  .withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(
              color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                  .withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

// ── Method chip ────────────────────────────────────────────────────────────────

class _MethodChip extends StatelessWidget {
  final CustomerPayMethod method;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _MethodChip({
    required this.method,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = method.color;
    final bg = selected
        ? c.withValues(alpha: 0.12)
        : (isDark ? AppColors.darkBackground : AppColors.warmOffWhite);
    final border = selected ? c : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(method.icon, size: 14, color: selected ? c : AppColors.darkGray),
          const SizedBox(width: 5),
          Text(
            method.label,
            style: AppTextStyles.caption().copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? c : AppColors.darkGray,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Method-specific panels ─────────────────────────────────────────────────────

class _CashPanel extends StatelessWidget {
  final bool isDark;

  const _CashPanel({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      ),
      child: Row(children: [
        const Icon(Icons.money_outlined,
            size: 14, color: Color(0xFF059669)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Saisissez le montant en espèces reçu ci-dessus.',
            style: AppTextStyles.caption(color: const Color(0xFF059669)),
          ),
        ),
      ]),
    );
  }
}

class _MonCashLive extends StatelessWidget {
  final double amountHtg;
  final bool amountOk;
  final bool isDark;
  final String? error;
  final bool preparing;
  final bool waiting;
  final bool paid;
  final String? paymentUrl;

  const _MonCashLive({
    super.key,
    required this.amountHtg,
    required this.amountOk,
    required this.isDark,
    required this.error,
    required this.preparing,
    required this.waiting,
    required this.paid,
    required this.paymentUrl,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final url = paymentUrl?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          !amountOk
              ? 'Saisissez le montant, puis MonCash prépare le paiement.'
              : url.isEmpty
                  ? 'Préparation du paiement MonCash. Les frais restent ceux de Digicel.'
                  : 'Le client scanne ce code, ou Payer ouvre MonCash sur cet appareil. Les frais restent ceux de Digicel.',
          style: AppTextStyles.body(color: muted),
        ),
        if (amountOk) ...[
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.local(context, amountHtg),
            style: AppTextStyles.price(),
          ),
        ],
        if (preparing) ...[
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ],
        if (url.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: url,
                size: 180,
                backgroundColor: AppColors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.nearBlack,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.nearBlack,
                ),
              ),
            ),
          ),
        ],
        _RemoteStatus(
          error: error,
          waiting: waiting,
          paid: paid,
          isDark: isDark,
        ),
      ],
    );
  }
}

class _CardLive extends StatelessWidget {
  final bool isDark;
  final CardChargePricing? pricing;
  final String orderLocalLabel;
  final String? error;
  final bool waiting;
  final bool paid;
  final _CardEntry entry;
  final bool entryLocked;
  final ValueChanged<_CardEntry> onEntry;
  final String? publishableKey;
  final bool configLoading;
  final String? configError;
  final StripeCardController cardController;
  final VoidCallback onCardReady;
  final ValueChanged<String> onCardError;
  final TextEditingController payerNameCtrl;
  final TextEditingController payerContactCtrl;
  final VoidCallback onPayerChanged;
  final String? shareUrl;
  final bool linkCopied;
  final VoidCallback onCopyLink;
  final VoidCallback onShareLink;

  const _CardLive({
    super.key,
    required this.isDark,
    required this.pricing,
    required this.orderLocalLabel,
    required this.error,
    required this.waiting,
    required this.paid,
    required this.entry,
    required this.entryLocked,
    required this.onEntry,
    required this.publishableKey,
    required this.configLoading,
    required this.configError,
    required this.cardController,
    required this.onCardReady,
    required this.onCardError,
    required this.payerNameCtrl,
    required this.payerContactCtrl,
    required this.onPayerChanged,
    required this.shareUrl,
    required this.linkCopied,
    required this.onCopyLink,
    required this.onShareLink,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final key = publishableKey?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _CardPathButton(
                label: 'Par carte',
                icon: Icons.credit_card_outlined,
                selected: entry == _CardEntry.form,
                onTap: entryLocked ? null : () => onEntry(_CardEntry.form),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CardPathButton(
                label: 'Lien de paiement',
                icon: Icons.link,
                selected: entry == _CardEntry.link,
                onTap: entryLocked ? null : () => onEntry(_CardEntry.link),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          entry == _CardEntry.form
              ? 'Saisissez la carte ici. Elle est envoyée à Stripe, pas à la caisse.'
              : 'Créez un lien à partager. Le compte est mis à jour quand le client a payé.',
          style: AppTextStyles.body(color: muted),
        ),
        const SizedBox(height: 10),
        if (pricing == null)
          Text(
            'Saisissez un montant. Le taux de change sert à encaisser en dollars.',
            style: AppTextStyles.body(color: muted),
          )
        else
          CardFeeBreakdown(
            pricing: pricing!,
            isDark: isDark,
            orderLocalLabel: orderLocalLabel,
          ),
        if (entry == _CardEntry.link) ...[
          const SizedBox(height: 10),
          if (shareUrl == null) ...[
            AppInput(
              label: 'Nom du payeur',
              controller: payerNameCtrl,
              onChanged: (_) => onPayerChanged(),
            ),
            const SizedBox(height: 8),
            AppInput(
              label: 'Téléphone ou e-mail',
              controller: payerContactCtrl,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => onPayerChanged(),
            ),
          ] else
            _ShareLinkBox(
              url: shareUrl!,
              isDark: isDark,
              copied: linkCopied,
              onCopy: onCopyLink,
              onShare: onShareLink,
            ),
        ],
        if (entry == _CardEntry.form &&
            configError != null &&
            configError!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            configError!,
            style: AppTextStyles.body(color: AppColors.boldRed),
          ),
        ],
        const SizedBox(height: 8),
        Text('Propulsé par Stripe', style: AppTextStyles.caption(color: muted)),
        if (entry == _CardEntry.form) ...[
          const SizedBox(height: 8),
          if (configLoading || key.isEmpty)
            Text(
              configLoading
                  ? 'Chargement du formulaire…'
                  : (configError ?? 'Formulaire carte indisponible.'),
              style: AppTextStyles.caption(
                color: configError == null ? muted : AppColors.boldRed,
              ),
            )
          else
            SizedBox(
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: StripeCardField(
                  publishableKey: key,
                  controller: cardController,
                  isDark: isDark,
                  onReady: onCardReady,
                  onError: onCardError,
                ),
              ),
            ),
        ],
        _RemoteStatus(
          error: error,
          waiting: waiting,
          paid: paid,
          isDark: isDark,
        ),
      ],
    );
  }
}

class _CardPathButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _CardPathButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    return Material(
      color: selected
          ? accent
          : (isDark ? AppColors.darkBackground : AppColors.white),
      borderRadius: BorderRadius.circular(AppConstants.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            border: Border.all(
              color: selected
                  ? accent
                  : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.white
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(
                    color: selected
                        ? AppColors.white
                        : (isDark ? AppColors.coolGray : AppColors.darkGray),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareLinkBox extends StatelessWidget {
  final String url;
  final bool isDark;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _ShareLinkBox({
    required this.url,
    required this.isDark,
    required this.copied,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : AppColors.lightBlue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Text(
            url,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(color: accent).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: copied ? 'Copié' : 'Copier',
                icon: copied ? Icons.check : Icons.copy_outlined,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: onCopy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                label: 'Partager',
                icon: Icons.share_outlined,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: onShare,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RemoteStatus extends StatelessWidget {
  final String? error;
  final bool waiting;
  final bool paid;
  final bool isDark;

  const _RemoteStatus({
    required this.error,
    required this.waiting,
    required this.paid,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (paid) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Paiement reçu.',
          style: AppTextStyles.body(color: AppColors.deepGreen),
        ),
      );
    }
    if (error != null && error!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(error!, style: AppTextStyles.body(color: AppColors.boldRed)),
      );
    }
    if (waiting) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'En attente du paiement…',
          style: AppTextStyles.body(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

ShopPdf _accountReceiptDocument(
  BuildContext context,
  Customer customer,
  _PaymentResult result,
) {
  return ShopPdf(
    shopName: shopNameFrom(context),
    title: 'REÇU',
    headline: 'Paiement de compte',
    number: result.receiptNumber,
    when: formatPdfStamp(result.paidAt),
    fields: [
      PdfField('Client', customer.name),
      PdfField('Paiement', result.method.label),
      if ((result.methodDetail ?? '').trim().isNotEmpty)
        PdfField('Détail', result.methodDetail!.trim()),
    ],
    totals: [
      PdfTotalLine(
        'Solde précédent',
        localMoney(context, result.previousBalance),
      ),
      PdfTotalLine('Payé', localMoney(context, result.amountPaid), strong: true),
      PdfTotalLine(
        'Solde restant',
        localMoney(context, result.remainingBalance),
      ),
    ],
  );
}

class _AccountReceiptView extends StatelessWidget {
  final Customer customer;
  final _PaymentResult result;
  final bool isDark;

  const _AccountReceiptView({
    required this.customer,
    required this.result,
    required this.isDark,
  });

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await buildShopPdf(
        format: PdfPageFormat.a4,
        document: _accountReceiptDocument(context, customer, result),
      );
      if (!context.mounted) return;
      await shareReceiptFile(
        bytes: bytes,
        filename: 'recu-${result.receiptNumber}.pdf',
        subject: 'Reçu ${result.receiptNumber}',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le document n\'a pas pu être préparé.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        (isDark ? AppColors.coolGray : AppColors.darkGray).withValues(alpha: 0.15);
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final settled = result.remainingBalance <= 0;
    final r = result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paiement confirmé',
                      style: AppTextStyles.h3(color: textColor).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      settled ? 'Compte soldé ✓' : 'Paiement partiel enregistré',
                      style: AppTextStyles.caption(
                        color: settled ? const Color(0xFF059669) : AppColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              AppCloseButton(onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReceiptCard(result: r, customer: customer),
                const SizedBox(height: 16),
                Text(
                  'Partager le reçu',
                  style: AppTextStyles.caption().copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _ShareButton(
                      icon: Icons.phone_android_outlined,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () => PaymentReceiptDialogs.showWhatsApp(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ShareButton(
                      icon: Icons.email_outlined,
                      label: 'E-mail',
                      color: AppColors.primaryBlue,
                      onTap: () => PaymentReceiptDialogs.showEmail(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ShareButton(
                      icon: Icons.print_outlined,
                      label: 'Imprimer',
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      onTap: () => PaymentReceiptDialogs.showPrint(
                        context,
                        receiptName: customer.name,
                        filename: 'recu-${r.receiptNumber}.pdf',
                        document: _accountReceiptDocument(context, customer, r),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                _ShareButton(
                  key: const Key('account-receipt-share'),
                  icon: Icons.share_outlined,
                  label: 'Partager',
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  onTap: () => _share(context),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                ),
              ),
              child: Text(
                'Terminé',
                style: AppTextStyles.body().copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Receipt card ───────────────────────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final _PaymentResult result;
  final Customer customer;

  const _ReceiptCard({required this.result, required this.customer});

  @override
  Widget build(BuildContext context) {
    final settled = result.remainingBalance <= 0;
    final dt = result.paidAt;
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Receipt header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Column(children: [
              Text('REÇU DE PAIEMENT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  )),
              const SizedBox(height: 2),
              Text(result.receiptNumber,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  )),
            ]),
          ),

          // Receipt body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Date + time
                Row(children: [
                  const Icon(Icons.access_time_outlined,
                      size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('$dateStr à $timeStr',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF64748B))),
                ]),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 10),

                // Customer info
                _ReceiptRow(
                    label: 'Client',
                    value: customer.name,
                    bold: true),
                _ReceiptRow(label: 'Téléphone', value: customer.phone),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 8),

                // Method
                Row(children: [
                  Text('Moyen',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF64748B))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          result.method.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(result.method.icon,
                          size: 11, color: result.method.color),
                      const SizedBox(width: 4),
                      Text(result.method.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: result.method.color,
                          )),
                    ]),
                  ),
                ]),
                if (result.methodDetail != null) ...[
                  const SizedBox(height: 4),
                  _ReceiptRow(label: 'Référence', value: result.methodDetail!),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 12),

                // Amount paid (prominent)
                Center(
                  child: Column(
                    children: [
                      const Text('MONTANT PAYÉ',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.local(context, result.amountPaid),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 10),

                // Balance summary
                _ReceiptRow(
                  label: 'Solde précédent',
                  value: CurrencyFormatter.local(
                      context, result.previousBalance),
                  valueColor: const Color(0xFFDC2626),
                ),
                _ReceiptRow(
                  label: 'Montant payé',
                  value:
                      '- ${CurrencyFormatter.local(context, result.amountPaid)}',
                  valueColor: const Color(0xFF059669),
                ),
                const Divider(height: 8, color: Color(0xFFE2E8F0)),
                _ReceiptRow(
                  label: 'Solde restant',
                  value: settled
                      ? 'Compte soldé'
                      : CurrencyFormatter.local(
                          context, result.remainingBalance),
                  bold: true,
                  valueColor:
                      settled ? const Color(0xFF059669) : const Color(0xFFDC2626),
                ),
              ],
            ),
          ),

          // Receipt footer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(10)),
              border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Text(
              'Merci pour votre paiement',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: const Color(0xFF64748B),
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            )),
        const Spacer(),
        Text(value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? const Color(0xFF1E293B),
            )),
      ]),
    );
  }
}

// ── Share button ───────────────────────────────────────────────────────────────

class _ShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(vertical: 9),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusButton)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

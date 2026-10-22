import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../printing/shop_pdf.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/payment_receipt_dialogs.dart';
import '../../widgets/app_close_button.dart';
import '../../widgets/phone_field.dart';

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
  // step 0 = payment input   step 1 = receipt
  int _step = 0;
  CustomerPayMethod _method = CustomerPayMethod.cash;
  _PaymentResult? _result;

  // Controllers
  final _amtCtrl = TextEditingController();
  final _moncashPhoneCtrl = TextEditingController();
  final _moncashTxCtrl = TextEditingController();

  double get _enteredAmount => double.tryParse(_amtCtrl.text) ?? 0;
  bool get _amountOverBalance => _enteredAmount > widget.balance;
  double get _remainingAfterPayment =>
      (_enteredAmount > 0 && !_amountOverBalance)
          ? (widget.balance - _enteredAmount).clamp(0.0, double.infinity)
          : widget.balance;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _moncashPhoneCtrl.dispose();
    _moncashTxCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged(String v) => setState(() {});

  void _confirm() {
    final amount = _enteredAmount;
    if (amount <= 0 || _amountOverBalance) return;

    final receiptNumber = _nextReceiptNumber();
    final previousBalance = widget.balance;
    final remaining = _remainingAfterPayment;

    String? methodDetail;
    if (_method == CustomerPayMethod.moncash &&
        _moncashPhoneCtrl.text.trim().isNotEmpty) {
      methodDetail = _moncashPhoneCtrl.text.trim();
    }

    ref.read(customerProvider.notifier).postPayment(
          customerId: widget.customer.id,
          amountHtg: amount,
          cashierName: 'Caissier',
          paymentMethodLabel: _method.label,
          receiptNumber: receiptNumber,
        );

    setState(() {
      _result = _PaymentResult(
        receiptNumber: receiptNumber,
        amountPaid: amount,
        previousBalance: previousBalance,
        remainingBalance: remaining,
        method: _method,
        methodDetail: methodDetail,
        paidAt: DateTime.now(),
      );
      _step = 1;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;

    return Dialog(
      backgroundColor: bg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _step == 0
              ? _buildPaymentStep(context, isDark)
              : _buildReceiptStep(context, isDark),
        ),
      ),
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
    final isValid = amount > 0 && !overBalance;

    return Column(
      key: const ValueKey('payment'),
      mainAxisSize: MainAxisSize.min,
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
            // Outstanding balance pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.boldRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.boldRed.withValues(alpha: 0.22)),
              ),
              child: Text(
                CurrencyFormatter.local(context, widget.balance),
                style: AppTextStyles.caption(color: AppColors.boldRed)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            AppCloseButton(onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Divider(height: 1, color: dividerColor),

        // ── Body (scrollable when content tall) ────────────────────────────
        SingleChildScrollView(
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
                    Text(
                      'Solde après paiement',
                      style: AppTextStyles.caption(),
                    ),
                    const Spacer(),
                    Text(
                      _remainingAfterPayment == 0
                          ? 'Settled ✓'
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
                        onTap: () => setState(() => _method = m),
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
              const SizedBox(height: 20),

              // ── Confirm button ───────────────────────────────────────────
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: isValid ? _confirm : null,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Confirmer le paiement',
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
            ],
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
        return _MonCashPanel(
          key: const ValueKey('moncash'),
          phoneCtrl: _moncashPhoneCtrl,
          txCtrl: _moncashTxCtrl,
          isDark: isDark,
        );
      case CustomerPayMethod.card:
        return _CardPanel(key: const ValueKey('card'), isDark: isDark);
    }
  }

  // ── Step 1: Receipt ────────────────────────────────────────────────────────

  Widget _buildReceiptStep(BuildContext context, bool isDark) {
    final r = _result!;
    final dividerColor =
        (isDark ? AppColors.coolGray : AppColors.darkGray)
            .withValues(alpha: 0.15);
    final textColor =
        isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final settled = r.remainingBalance <= 0;

    return Column(
      key: const ValueKey('receipt'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Success header ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 28, color: Color(0xFF059669)),
              ),
              const SizedBox(height: 8),
              Text('Paiement confirmé',
                  style: AppTextStyles.h3(color: textColor)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                settled
                    ? 'Compte soldé ✓'
                    : 'Paiement partiel enregistré',
                style: AppTextStyles.caption(
                    color: settled
                        ? const Color(0xFF059669)
                        : AppColors.amber),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),

        // ── Scrollable receipt body (capped so dialog stays compact) ─────────
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReceiptCard(result: r, customer: widget.customer),
                const SizedBox(height: 16),

                // ── Share row ────────────────────────────────────────────
                Text('Partager le reçu',
                    style: AppTextStyles.caption()
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _ShareButton(
                      icon: Icons.phone_android_outlined,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () =>
                          PaymentReceiptDialogs.showWhatsApp(context),
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
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray,
                      onTap: () => PaymentReceiptDialogs.showPrint(
                        context,
                        receiptName: widget.customer.name,
                        filename: 'recu-${r.receiptNumber}.pdf',
                        document: ShopPdf(
                          shopName: shopNameFrom(context),
                          title: 'REÇU',
                          headline: 'Paiement de compte',
                          number: r.receiptNumber,
                          when: formatPdfStamp(r.paidAt),
                          fields: [
                            PdfField('Client', widget.customer.name),
                            PdfField('Paiement', r.method.label),
                            if ((r.methodDetail ?? '').trim().isNotEmpty)
                              PdfField('Détail', r.methodDetail!.trim()),
                          ],
                          totals: [
                            PdfTotalLine(
                              'Solde précédent',
                              localMoney(context, r.previousBalance),
                            ),
                            PdfTotalLine(
                              'Payé',
                              localMoney(context, r.amountPaid),
                              strong: true,
                            ),
                            PdfTotalLine(
                              'Solde restant',
                              localMoney(context, r.remainingBalance),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Done button ──────────────────────────────────────────
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusButton)),
                    ),
                    child: Text('Terminé',
                        style: AppTextStyles.body().copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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

class _MonCashPanel extends StatelessWidget {
  final TextEditingController phoneCtrl;
  final TextEditingController txCtrl;
  final bool isDark;

  const _MonCashPanel({
    super.key,
    required this.phoneCtrl,
    required this.txCtrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelField(
          controller: phoneCtrl,
          label: 'Numéro MonCash',
          keyboardType: TextInputType.phone,
          formatters: InputFormatters.phone,
          isDark: isDark,
          prefixIcon: Icons.phone_android_outlined,
        ),
        const SizedBox(height: 10),
        _PanelField(
          controller: txCtrl,
          label: 'N° de transaction (facultatif)',
          isDark: isDark,
          prefixIcon: Icons.tag_outlined,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          ),
          child: Text(
            'Vérifiez la confirmation MonCash avant de confirmer le paiement.',
            style: AppTextStyles.caption(
                color: const Color(0xFF7C3AED)),
          ),
        ),
      ],
    );
  }
}

class _CardPanel extends StatefulWidget {
  final bool isDark;

  const _CardPanel({super.key, required this.isDark});

  @override
  State<_CardPanel> createState() => _CardPanelState();
}

class _CardPanelState extends State<_CardPanel> {
  final _cardCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  @override
  void dispose() {
    _cardCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    const blue = Color(0xFF2563EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.credit_card_outlined,
              size: 15, color: isDark ? AppColors.skyBlue : blue),
          const SizedBox(width: 6),
          Text('Détails de la carte',
              style: AppTextStyles.caption()
                  .copyWith(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        _PanelField(
          controller: _cardCtrl,
          label: 'Numéro de carte',
          keyboardType: TextInputType.number,
          formatters: InputFormatters.cardNumber,
          isDark: isDark,
          prefixIcon: Icons.credit_card_outlined,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _PanelField(
              controller: _expiryCtrl,
              label: 'Expiration (MM/AA)',
              keyboardType: TextInputType.number,
              formatters: InputFormatters.cardExpiry,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PanelField(
              controller: _cvvCtrl,
              label: 'CVV',
              keyboardType: TextInputType.number,
              formatters: InputFormatters.cardCvv,
              isDark: isDark,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Propulsé par Stripe',
            style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)
                .copyWith(fontSize: 10)),
      ],
    );
  }
}

// ── Panel shared text field ────────────────────────────────────────────────────

class _PanelField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final bool isDark;

  const _PanelField({
    required this.controller,
    required this.label,
    this.prefixIcon,
    this.keyboardType,
    this.formatters,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (keyboardType == TextInputType.phone) {
      return PhoneField(controller: controller, label: label);
    }
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: AppTextStyles.body().copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption(),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 16,
                color: isDark ? AppColors.coolGray : AppColors.darkGray)
            : null,
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
                  Text('$dateStr at $timeStr',
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
                      ? 'Settled ✓'
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/payments/card_charge_pricing.dart';
import '../../core/payments/open_payment_url.dart';
import '../../core/payments/payments_client.dart';
import '../../core/payments/stripe_card_field.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/widgets/card_fee_breakdown.dart';
import '../../core/mock/mock_retail_data.dart';
import '../models/sale_measure.dart';
import '../../core/mock/mock_retail_orders.dart';
import '../../core/models/customer.dart';
import '../../core/models/order_history.dart';
import '../../core/models/retail_check_payment.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import '../../core/permissions/client_credit_grant.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/permission_settings_provider.dart';
import '../../core/providers/staff_session_provider.dart';
import '../../core/widgets/credit_grant_pin_dialog.dart';
import '../../core/providers/tax_settings_provider.dart';
import '../../core/utils/operator_name.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/phone_field.dart';
import '../models/retail_cart_entry.dart';
import '../receipt/sale_receipt_text.dart';
import '../widgets/sale_receipt_panel.dart';
import '../widgets/check_payment_form.dart';
import '../widgets/check_photo_pick.dart';
import '../widgets/product_photo_pick.dart';
import '../../core/widgets/app_close_button.dart';

/// Opens the retail checkout slide-over (desktop) / near-full-width (narrow).
Future<void> showRetailCheckoutDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<RetailCartEntry> cart,
  required double discountPercent,
  bool isQuote = false,
  MockRetailQuote? existingQuote,
  int? initialStepIndex,
  required VoidCallback onSuccess,
  VoidCallback? onQuoteSaved,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Checkout',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
    pageBuilder: (ctx, _, __) {
      final w = MediaQuery.sizeOf(ctx).width;
      final panelW = AppConstants.sidePanelWidth(w, 480.0);
      return Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: panelW,
              child: RetailCheckoutWizard(
                cart: cart,
                discountPercent: discountPercent,
                isQuote: isQuote,
                existingQuote: existingQuote,
                initialStepIndex: initialStepIndex,
                onSuccess: onSuccess,
                onQuoteSaved: onQuoteSaved,
                embedded: false,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class RetailCheckoutWizard extends ConsumerStatefulWidget {
  final List<RetailCartEntry> cart;
  final double discountPercent;
  final bool isQuote;
  final MockRetailQuote? existingQuote;
  final int? initialStepIndex;
  final VoidCallback onSuccess;
  final VoidCallback? onQuoteSaved;

  /// When true (POS right column / slide-over), do not [Navigator.pop] — use [onDismiss].
  final bool embedded;

  /// Embedded only: close checkout and return to cart (parent clears checkout state).
  final VoidCallback? onDismiss;

  const RetailCheckoutWizard({
    super.key,
    required this.cart,
    required this.discountPercent,
    this.isQuote = false,
    this.existingQuote,
    this.initialStepIndex,
    required this.onSuccess,
    this.onQuoteSaved,
    this.embedded = false,
    this.onDismiss,
  });

  @override
  ConsumerState<RetailCheckoutWizard> createState() =>
      _RetailCheckoutWizardState();
}

class _RetailCheckoutWizardState extends ConsumerState<RetailCheckoutWizard> {
  late int _step;
  late String _checkoutId;

  final _clientNameCtrl = TextEditingController();
  final _clientEmailCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _deliveryLocationCtrl = TextEditingController();
  final _deliveryFeeCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();

  RetailFulfillmentMode _fulfillment = RetailFulfillmentMode.inStore;
  double _deliveryFee = 0;
  String _searchQuery = '';

  /// Phone from directory selection (not the search field text).
  String _linkedClientPhone = '';

  /// Name last chosen from the client search. Editing that name clears it.
  String? _directoryClientName;
  bool _submitting = false;

  /// Shown on success screen (mock sale #).
  int _completedSaleNumber = 0;

  /// Check was recorded and still has to clear.
  bool _awaitingCheckClearance = false;

  /// Unpaid remainder from the payment the cashier just confirmed.
  double _receiptBalanceDue = 0;

  /// Sale recorded by the last successful payment. The receipt reads this.
  RetailOrder? _completedOrder;

  @override
  void initState() {
    super.initState();
    final q = widget.existingQuote;
    _checkoutId = q?.checkoutId ?? QuotesNotifier.newCheckoutId();
    if (q != null) {
      _clientNameCtrl.text = q.clientName ?? '';
      _clientEmailCtrl.text = q.clientEmail ?? '';
      _linkedClientPhone = q.clientPhone ?? '';
      _searchCtrl.text = '';
      _searchQuery = '';
      _fulfillment = q.fulfillmentMode;
      _deliveryLocationCtrl.text = q.deliveryLocation ?? '';
      final quoteName = (q.clientName ?? '').trim();
      final quotePhone = (q.clientPhone ?? '').trim();
      if (quoteName.isNotEmpty && quotePhone.isNotEmpty) {
        _directoryClientName = quoteName;
      }
      final deliveryPhone = (q.deliveryPhone ?? '').trim();
      if (q.fulfillmentMode == RetailFulfillmentMode.delivery &&
          deliveryPhone.isNotEmpty) {
        _clientPhoneCtrl.text = deliveryPhone;
      } else if (quotePhone.isNotEmpty) {
        _clientPhoneCtrl.text = quotePhone;
      } else {
        _clientPhoneCtrl.text = deliveryPhone;
      }
    }
    _clientNameCtrl.addListener(_onSaleClientNameEdited);
    // Steps: 0–2 checkout; 3 = payment confirmed (after pay only).
    const lastPayStep = 2;
    final initial = widget.initialStepIndex ?? (q != null ? lastPayStep : 0);
    _step = initial.clamp(0, lastPayStep);
  }

  void _onSaleClientNameEdited() {
    final picked = _directoryClientName;
    if (picked == null) return;
    if (_clientNameCtrl.text.trim() == picked) return;
    _directoryClientName = null;
    _linkedClientPhone = '';
    _clientPhoneCtrl.clear();
    if (mounted) setState(() {});
  }

  /// Phone saved on the sale: the field on this step, or the directory number.
  String get _contactPhone {
    final typed = _clientPhoneCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    return _linkedClientPhone.trim();
  }

  bool get _clientFromDirectory {
    final picked = _directoryClientName;
    return picked != null &&
        picked == _clientNameCtrl.text.trim() &&
        _linkedClientPhone.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _clientNameCtrl.removeListener(_onSaleClientNameEdited);
    _clientNameCtrl.dispose();
    _clientEmailCtrl.dispose();
    _searchCtrl.dispose();
    _deliveryLocationCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    _clientPhoneCtrl.dispose();
    super.dispose();
  }

  RetailSettings get _retailSettings => ref.watch(retailSettingsProvider);

  /// Fulfillment picker (In store + optional Pickup / Delivery) is shown only if at least one extra mode is enabled.
  bool get _fulfillmentSectionVisible =>
      _retailSettings.pickupEnabled || _retailSettings.deliveryEnabled;

  bool get _pickupEnabled => _retailSettings.pickupEnabled;

  bool get _deliveryOptionEnabled => _retailSettings.deliveryEnabled;

  bool get _isDeliveryMode =>
      _deliveryOptionEnabled && _fulfillment == RetailFulfillmentMode.delivery;

  static bool _fulfillmentAllowed(RetailFulfillmentMode m, RetailSettings s) {
    if (!s.pickupEnabled && !s.deliveryEnabled) {
      return m == RetailFulfillmentMode.inStore;
    }
    switch (m) {
      case RetailFulfillmentMode.inStore:
        return true;
      case RetailFulfillmentMode.pickup:
        return s.pickupEnabled;
      case RetailFulfillmentMode.delivery:
        return s.deliveryEnabled;
    }
  }

  int get _paymentStepIndex => 2;

  int get _successStepIndex => 3;

  String get _stepTitle {
    switch (_step) {
      case 0:
        return _fulfillmentSectionVisible ? 'Client et livraison' : 'Client';
      case 1:
        return 'Récapitulatif';
      case 2:
        return 'Paiement';
      case 3:
        return 'Paiement';
      default:
        return 'Checkout';
    }
  }

  String _successContextSubtitle() {
    final name = _clientNameCtrl.text.trim();
    final modeLabel = !_fulfillmentSectionVisible
        ? RetailFulfillmentMode.inStore.label
        : _fulfillment.label;
    if (name.isEmpty) return modeLabel;
    return '$modeLabel · $name';
  }

  void _onFulfillmentChanged(RetailFulfillmentMode mode) {
    setState(() {
      _fulfillment = mode;
      if (mode == RetailFulfillmentMode.delivery &&
          _clientPhoneCtrl.text.trim().isEmpty &&
          _linkedClientPhone.trim().isNotEmpty) {
        _clientPhoneCtrl.text = _linkedClientPhone;
      }
    });
  }

  void _onPickMockCustomer(MockCustomer c) {
    setState(() {
      _directoryClientName = c.name;
      _clientNameCtrl.text = c.name;
      _linkedClientPhone = c.phone;
      _clientPhoneCtrl.text = c.phone;
      _searchCtrl.clear();
      _searchQuery = '';
    });
  }

  void _clearSelectedClient() {
    setState(() {
      _directoryClientName = null;
      _linkedClientPhone = '';
      _clientNameCtrl.clear();
      _clientPhoneCtrl.clear();
      _searchCtrl.clear();
      _searchQuery = '';
    });
  }

  void _finishPaymentSuccess() {
    if (!widget.embedded && context.mounted) {
      Navigator.of(context).pop();
    }
    widget.onSuccess();
  }

  void _closeShell() {
    if (widget.embedded) {
      widget.onDismiss?.call();
    } else if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  double _subtotal(List<RetailCartEntry> lines) =>
      lines.fold(0.0, (s, e) => s + e.unitPriceHtg * e.quantity);

  double _discountAmt(double sub) => sub * (widget.discountPercent / 100);

  double _taxable(double sub, double disc) => sub - disc;

  double _taxAmt(double taxable) {
    if (!ref.watch(taxEnabledProvider)) return 0;
    return taxable * (ref.watch(taxPercentProvider) / 100);
  }

  double _gratuityAmt(double taxable) {
    if (!ref.watch(gratuityEnabledProvider)) return 0;
    return taxable * (ref.watch(gratuityPercentProvider) / 100);
  }

  bool _validateClientStepForQuote() {
    if (!widget.isQuote) return true;
    final hasName = _clientNameCtrl.text.trim().isNotEmpty;
    final hasContact =
        _contactPhone.isNotEmpty ||
        _clientEmailCtrl.text.trim().isNotEmpty;
    return hasName && hasContact;
  }

  bool _validateDeliveryStep() {
    if (!_isDeliveryMode) return true;
    return _deliveryLocationCtrl.text.trim().isNotEmpty &&
        _clientPhoneCtrl.text.trim().isNotEmpty;
  }

  void _next() {
    if (_step == 0) {
      if (widget.isQuote && !_validateClientStepForQuote()) {
        final hasName = _clientNameCtrl.text.trim().isNotEmpty;
        final message = !hasName
            ? 'Le nom du client est obligatoire pour un devis.'
            : 'Un téléphone ou un e-mail est obligatoire pour un devis.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: AppTextStyles.body(color: AppColors.white),
            ),
            backgroundColor: AppColors.boldRed,
          ),
        );
        return;
      }
      if (_isDeliveryMode && !_validateDeliveryStep()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'L\'adresse et le téléphone sont obligatoires pour la livraison.',
              style: AppTextStyles.body(color: AppColors.white),
            ),
            backgroundColor: AppColors.boldRed,
          ),
        );
        return;
      }
    }
    if (_step < _paymentStepIndex) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _saveQuote() {
    // Snapshot prices at save time — future catalog changes won't affect this quote.
    final lines = widget.cart
        .map(
          (e) => MockQuoteLine(
            product: e.detailLabel.isEmpty
                ? e.product
                : e.product.copyWith(name: e.lineLabel),
            quantity: e.quantity,
            unitPriceHtg: e.unitPriceHtg,
            unitPriceUsd: e.product.sellingPriceUsd,
            measure: e.measure,
          ),
        )
        .toList();
    final existing = widget.existingQuote;
    if (existing != null && widget.isQuote) {
      ref
          .read(quotesProvider.notifier)
          .updateQuote(
            existing.copyWith(
              lines: lines,
              clientName: _clientNameCtrl.text.trim().isEmpty
                  ? null
                  : _clientNameCtrl.text.trim(),
              clientPhone: _contactPhone.isEmpty ? null : _contactPhone,
              clientEmail: _clientEmailCtrl.text.trim().isEmpty
                  ? null
                  : _clientEmailCtrl.text.trim(),
              fulfillmentMode: _fulfillmentSectionVisible
                  ? _fulfillment
                  : RetailFulfillmentMode.inStore,
              deliveryLocation: _isDeliveryMode
                  ? _deliveryLocationCtrl.text.trim()
                  : null,
              deliveryPhone: _isDeliveryMode
                  ? (_contactPhone.isEmpty ? null : _contactPhone)
                  : null,
              discountPercent: widget.discountPercent,
              paymentLinkSent: false,
            ),
          );
    } else {
      ref
          .read(quotesProvider.notifier)
          .add(
            MockRetailQuote(
              id: 'qte_${DateTime.now().millisecondsSinceEpoch}',
              quoteNumber: QuotesNotifier.newQuoteNumber(),
              checkoutId: _checkoutId,
              lines: lines,
              clientName: _clientNameCtrl.text.trim().isEmpty
                  ? null
                  : _clientNameCtrl.text.trim(),
              clientPhone: _contactPhone.isEmpty ? null : _contactPhone,
              clientEmail: _clientEmailCtrl.text.trim().isEmpty
                  ? null
                  : _clientEmailCtrl.text.trim(),
              fulfillmentMode: _fulfillmentSectionVisible
                  ? _fulfillment
                  : RetailFulfillmentMode.inStore,
              deliveryLocation: _isDeliveryMode
                  ? _deliveryLocationCtrl.text.trim()
                  : null,
              deliveryPhone: _isDeliveryMode
                  ? (_contactPhone.isEmpty ? null : _contactPhone)
                  : null,
              discountPercent: widget.discountPercent,
              status: MockRetailQuoteStatus.draft,
              createdAt: DateTime.now(),
            ),
          );
    }
    _closeShell();
    if (widget.onQuoteSaved != null) {
      widget.onQuoteSaved!();
    } else {
      widget.onSuccess();
    }
  }

  List<String>? _stockFailures(List<RetailCartEntry> lines) {
    final products = ref.read(mockProductsProvider);
    final failures = <String>[];
    final wanted = <int, int>{};
    for (final e in lines) {
      final matches = products.where((p) => p.id == e.product.id).toList();
      if (matches.isEmpty) {
        failures.add('${e.lineLabel} — plus au catalogue');
        continue;
      }
      if (!matches.first.trackStock) continue;
      wanted[e.product.id] = (wanted[e.product.id] ?? 0) + e.stockUnits;
    }
    for (final entry in wanted.entries) {
      final live = products.firstWhere((p) => p.id == entry.key);
      if (entry.value > live.stockQuantity) {
        final unit = live.saleMode == SaleMode.roll ? ' po' : '';
        failures.add(
          '${live.name} — demandé ${entry.value}$unit, disponible ${live.stockQuantity}$unit',
        );
      }
    }
    return failures.isEmpty ? null : failures;
  }

  Future<void> _showStockDialog(List<String> lines) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.boldRed),
            const SizedBox(width: AppConstants.spacing8),
            Expanded(
              child: Text(
                'Rupture de stock',
                style: AppTextStyles.h3(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ces articles ne sont pas disponibles dans la quantité demandée :',
                style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              const SizedBox(height: AppConstants.spacing12),
              ...lines.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spacing4),
                  child: Text(
                    '• $t',
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: AppTextStyles.button(color: AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final retailSettings = ref.watch(retailSettingsProvider);
    ref.listen<RetailSettings>(retailSettingsProvider, (prev, next) {
      if (!mounted) return;
      if (!_fulfillmentAllowed(_fulfillment, next)) {
        setState(() => _fulfillment = RetailFulfillmentMode.inStore);
      }
    });
    if (!_fulfillmentAllowed(_fulfillment, retailSettings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = ref.read(retailSettingsProvider);
        if (!_fulfillmentAllowed(_fulfillment, s)) {
          setState(() => _fulfillment = RetailFulfillmentMode.inStore);
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.warmOffWhite;
    final lines = widget.cart;
    final sub = _subtotal(lines);
    final disc = _discountAmt(sub);
    final taxable = _taxable(sub, disc);
    final tax = _taxAmt(taxable);
    final grat = _gratuityAmt(taxable);
    final deliveryFee = _isDeliveryMode ? _deliveryFee : 0.0;
    final total = taxable + tax + grat + deliveryFee;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step != _successStepIndex) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing16,
                AppConstants.spacing12,
                AppConstants.spacing8,
                AppConstants.spacing8,
              ),
              child: Row(
                children: [
                  AppCloseButton(onPressed: _submitting ? null : _closeShell),
                  Expanded(
                    child: Text(
                      _stepTitle,
                      style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  if (_step > 0 && _step <= _paymentStepIndex)
                    TextButton(
                      onPressed: _submitting ? null : _back,
                      child: Text(
                        'Retour',
                        style: AppTextStyles.caption(
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: AppConstants.animFast,
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: _buildStepContent(
                key: ValueKey(_step),
                isDark: isDark,
                lines: lines,
                sub: sub,
                disc: disc,
                taxable: taxable,
                tax: tax,
                grat: grat,
                deliveryFee: deliveryFee,
                total: total,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent({
    required Key key,
    required bool isDark,
    required List<RetailCartEntry> lines,
    required double sub,
    required double disc,
    required double taxable,
    required double tax,
    required double grat,
    required double deliveryFee,
    required double total,
  }) {
    if (_step == 0) {
      return KeyedSubtree(
        key: key,
        child: _ClientStep(
          clientNameCtrl: _clientNameCtrl,
          clientEmailCtrl: _clientEmailCtrl,
          searchCtrl: _searchCtrl,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          isQuote: widget.isQuote,
          onNext: _next,
          showFulfillmentSection: _fulfillmentSectionVisible,
          pickupEnabled: _pickupEnabled,
          deliveryOptionEnabled: _deliveryOptionEnabled,
          fulfillment: _fulfillment,
          onFulfillmentChanged: _onFulfillmentChanged,
          onPickMockCustomer: _onPickMockCustomer,
          selectedClientName: _clientFromDirectory
              ? _clientNameCtrl.text.trim()
              : null,
          selectedClientPhone: _linkedClientPhone.trim(),
          onClearSelectedClient: _clearSelectedClient,
          clientPhoneCtrl: _clientPhoneCtrl,
          phoneRequired: _isDeliveryMode,
          deliveryLocationCtrl: _deliveryLocationCtrl,
          deliveryFeeCtrl: _deliveryFeeCtrl,
          onDeliveryFeeChanged: (v) =>
              setState(() => _deliveryFee = double.tryParse(v) ?? 0),
        ),
      );
    }
    const reviewIndex = 1;
    if (_step == reviewIndex) {
      return KeyedSubtree(
        key: key,
        child: _ReviewStep(
          lines: lines,
          discountPercent: widget.discountPercent,
          subtotal: sub,
          discountAmt: disc,
          taxable: taxable,
          tax: tax,
          gratuity: grat,
          total: total,
          clientName: _clientNameCtrl.text.trim(),
          linkedClientPhone: _contactPhone,
          fulfillment: _fulfillmentSectionVisible
              ? _fulfillment
              : RetailFulfillmentMode.inStore,
          showFulfillmentChip: _fulfillmentSectionVisible,
          deliveryLocation: _deliveryLocationCtrl.text.trim(),
          deliveryPhone: _isDeliveryMode ? _contactPhone : '',
          deliveryFee: deliveryFee,
          showDeliveryFeeRow: _isDeliveryMode,
          isDark: isDark,
          isQuote: widget.isQuote,
          isUpdatingQuote: widget.existingQuote != null && widget.isQuote,
          onPay: () => setState(() => _step = _paymentStepIndex),
          onSaveQuote: _saveQuote,
        ),
      );
    }
    if (_step == _paymentStepIndex) {
      return KeyedSubtree(
        key: key,
        child: _RetailPaymentPanel(
          total: total,
          checkoutId: _checkoutId,
          knownClientName: _clientNameCtrl.text.trim(),
          knownClientPhone: _clientFromDirectory
              ? _linkedClientPhone.trim()
              : _clientPhoneCtrl.text.trim(),
          clientFromDirectory: _clientFromDirectory,
          submitting: _submitting,
          onValidateStock: () async {
            setState(() => _submitting = true);
            final fails = _stockFailures(lines);
            if (fails != null) {
              await _showStockDialog(fails);
              if (mounted) setState(() => _submitting = false);
              return false;
            }
            return true;
          },
          onConfirm: (
            method, {
            RetailCheckPayment? check,
            double? amountPaidHtg,
            double balanceDueHtg = 0,
            Customer? creditCustomer,
            String? creditAuthorizedBy,
          }) async {
            final map = <int, int>{};
            for (final e in lines) {
              map[e.product.id] = (map[e.product.id] ?? 0) + e.stockUnits;
            }
            final now = DateTime.now();
            final saleNo = 100 + (now.millisecondsSinceEpoch % 8999);
            final clientName = _clientNameCtrl.text.trim();
            final clientEmail = _clientEmailCtrl.text.trim();
            final awaitingCheck = method == PaymentMethodType.check &&
                !(check?.cleared ?? false);
            final partial = !awaitingCheck && balanceDueHtg > 0.009;
            final creditName = creditCustomer?.name.trim() ?? '';
            final creditPhone = creditCustomer?.phone.trim() ?? '';
            final operator = currentOperatorName(
              staffName: ref.read(staffSessionProvider)?.employeeName,
              accountName: ref.read(authProvider).userName,
            );
            final sale = RetailOrder(
                    id: 'pos-$_checkoutId',
                    orderNumber: 'ORD-${now.year}-$saleNo',
                    fromQuoteId: widget.existingQuote?.id,
                    clientName: creditName.isNotEmpty
                        ? creditName
                        : (clientName.isEmpty ? null : clientName),
                    clientPhone: creditPhone.isNotEmpty
                        ? creditPhone
                        : (_contactPhone.isEmpty ? null : _contactPhone),
                    clientEmail: clientEmail.isEmpty ? null : clientEmail,
                    fulfillmentMode: _fulfillmentSectionVisible
                        ? _fulfillment
                        : RetailFulfillmentMode.inStore,
                    status: awaitingCheck
                        ? RetailOrderStatus.checkPending
                        : partial
                            ? RetailOrderStatus.partiallyPaid
                            : RetailOrderStatus.paid,
                    amountPaidHtg: partial ? (amountPaidHtg ?? 0) : null,
                    balanceDueHtg: partial ? balanceDueHtg : null,
                    paymentSource: RetailPaymentSource.pos,
                    paymentMethod: method,
                    checkPayment: method == PaymentMethodType.check
                        ? check
                        : null,
                    lines: [
                      for (final e in lines)
                        RetailOrderLine(
                          productName: e.lineLabel,
                          productId: e.product.id,
                          quantity: e.quantity,
                          unitPriceHtg: e.unitPriceHtg,
                          unitPriceUsd: e.product.sellingPriceUsd,
                        ),
                    ],
                    discountPercent: widget.discountPercent,
                    taxPercent: ref.read(taxEnabledProvider)
                        ? ref.read(taxPercentProvider)
                        : 0,
                    serviceChargePercent: ref.read(gratuityEnabledProvider)
                        ? ref.read(gratuityPercentProvider)
                        : 0,
                    deliveryFee: deliveryFee,
                    deliveryLocation: _isDeliveryMode
                        ? _deliveryLocationCtrl.text.trim()
                        : null,
                    deliveryPhone: _isDeliveryMode
                        ? (_contactPhone.isEmpty ? null : _contactPhone)
                        : null,
                    createdAt: now,
                    paidAt: now,
                    recordedBy: operator,
                  );
            if (partial && creditCustomer != null) {
              ref.read(customerProvider.notifier).postCharge(
                    customerId: creditCustomer.id,
                    amountHtg: total,
                    paidAmountHtg: amountPaidHtg ?? 0,
                    linkedOrderId: sale.id,
                    cashierName: operator,
                    description: creditAuthorizedBy == null
                        ? 'Solde de la commande ${sale.orderNumber}'
                        : 'Solde de la commande ${sale.orderNumber} · Autorisé par $creditAuthorizedBy',
                  );
            }
            ref.read(retailOrdersProvider.notifier).add(sale);
            ref.read(mockProductsProvider.notifier).applySale(map);
            ref
                .read(retailInventoryLedgerProvider.notifier)
                .recordSalesFromCheckout(map, DateTime.now());
            if (widget.existingQuote != null) {
              ref
                  .read(quotesProvider.notifier)
                  .convertToOrder(widget.existingQuote!.id);
            }
            if (!context.mounted) return;
            setState(() {
              _submitting = false;
              _completedSaleNumber = saleNo;
              _completedOrder = sale;
              _awaitingCheckClearance = awaitingCheck;
              _receiptBalanceDue = partial ? balanceDueHtg : 0;
              _step = _successStepIndex;
            });
          },
        ),
      );
    }
    if (_step == _successStepIndex) {
      final sale = _completedOrder;
      if (sale == null) {
        return KeyedSubtree(key: key, child: const SizedBox.shrink());
      }
      return KeyedSubtree(
        key: key,
        child: SaleReceiptPanel(
          order: sale,
          figures: SaleReceiptFigures(
            subtotal: sub,
            discountPercent: widget.discountPercent,
            discountAmount: disc,
            taxPercent: ref.watch(taxEnabledProvider)
                ? ref.watch(taxPercentProvider)
                : 0,
            taxAmount: tax,
            servicePercent: ref.watch(gratuityEnabledProvider)
                ? ref.watch(gratuityPercentProvider)
                : 0,
            serviceAmount: grat,
            deliveryFee: deliveryFee,
            total: total,
            balanceDue: _receiptBalanceDue,
          ),
          contextSubtitle: _successContextSubtitle(),
          statusLine: _awaitingCheckClearance
              ? 'Vente n°$_completedSaleNumber — chèque en attente'
              : _receiptBalanceDue > 0.009
                  ? 'Vente n°$_completedSaleNumber partiellement payée'
                  : 'Vente n°$_completedSaleNumber payée',
          onDone: _finishPaymentSuccess,
        ),
      );
    }
    return KeyedSubtree(key: key, child: const SizedBox.shrink());
  }
}

// ─── Step 0: Client ───────────────────────────────────────────────────────────

class _ClientStep extends ConsumerWidget {
  final TextEditingController clientNameCtrl;
  final TextEditingController clientEmailCtrl;
  final TextEditingController searchCtrl;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool isQuote;
  final VoidCallback onNext;
  final bool showFulfillmentSection;
  final bool pickupEnabled;
  final bool deliveryOptionEnabled;
  final RetailFulfillmentMode fulfillment;
  final ValueChanged<RetailFulfillmentMode> onFulfillmentChanged;
  final void Function(MockCustomer c) onPickMockCustomer;
  final String? selectedClientName;
  final String selectedClientPhone;
  final VoidCallback onClearSelectedClient;
  final TextEditingController clientPhoneCtrl;
  final bool phoneRequired;
  final TextEditingController deliveryLocationCtrl;
  final TextEditingController deliveryFeeCtrl;
  final ValueChanged<String> onDeliveryFeeChanged;

  const _ClientStep({
    required this.clientNameCtrl,
    required this.clientEmailCtrl,
    required this.searchCtrl,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.isQuote,
    required this.onNext,
    required this.showFulfillmentSection,
    required this.pickupEnabled,
    required this.deliveryOptionEnabled,
    required this.fulfillment,
    required this.onFulfillmentChanged,
    required this.onPickMockCustomer,
    required this.selectedClientName,
    required this.selectedClientPhone,
    required this.onClearSelectedClient,
    required this.clientPhoneCtrl,
    required this.phoneRequired,
    required this.deliveryLocationCtrl,
    required this.deliveryFeeCtrl,
    required this.onDeliveryFeeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mockList = ref.watch(mockCustomersProvider);
    final pickedName = selectedClientName?.trim() ?? '';
    final clientSelected = pickedName.isNotEmpty;
    final results = clientSelected || searchQuery.trim().isEmpty
        ? <MockCustomer>[]
        : mockList
              .where(
                (c) =>
                    c.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    c.phone.contains(searchQuery),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppConstants.spacing12,
              right: AppConstants.spacing12,
              top: AppConstants.spacing12,
              bottom:
                  MediaQuery.of(context).viewInsets.bottom +
                  AppConstants.spacing8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Client',
                  style: AppTextStyles.h3(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                if (!clientSelected) ...[
                  TextField(
                    key: const Key('checkout-client-search'),
                    controller: searchCtrl,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      labelText: 'Rechercher un client',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                      isDense: true,
                    ),
                  ),
                  if (results.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacing8),
                    ...results.map(
                      (c) => Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name, style: AppTextStyles.body()),
                          subtitle: Text(
                            c.phone,
                            style: AppTextStyles.caption(),
                          ),
                          onTap: () => onPickMockCustomer(c),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spacing8),
                ],
                if (clientSelected)
                  _SelectedClientCard(
                    name: pickedName,
                    phone: selectedClientPhone,
                    onClear: onClearSelectedClient,
                  )
                else
                  TextField(
                    key: const Key('checkout-client-name'),
                    controller: clientNameCtrl,
                    decoration: InputDecoration(
                      labelText: isQuote
                          ? 'Nom du client *'
                          : 'Nom du client (facultatif)',
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                if (isQuote) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  TextField(
                    controller: clientEmailCtrl,
                    decoration: InputDecoration(
                      labelText: 'E-mail (obligatoire sans téléphone)',
                      prefixIcon: const Icon(Icons.email_outlined, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppConstants.spacing4),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 13,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Le nom est obligatoire. Le téléphone ou l\'e-mail est obligatoire pour envoyer un lien de paiement.',
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!clientSelected) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  PhoneField(
                    key: const Key('checkout-client-phone'),
                    controller: clientPhoneCtrl,
                    label: phoneRequired
                        ? 'Téléphone *'
                        : 'Téléphone (facultatif)',
                  ),
                ],
                if (showFulfillmentSection) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  Text(
                    'Remise',
                    style: AppTextStyles.h3(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  SegmentedButton<RetailFulfillmentMode>(
                    segments: [
                      const ButtonSegment<RetailFulfillmentMode>(
                        value: RetailFulfillmentMode.inStore,
                        label: Text('En magasin'),
                        icon: Icon(Icons.storefront_outlined, size: 16),
                      ),
                      if (pickupEnabled)
                        const ButtonSegment<RetailFulfillmentMode>(
                          value: RetailFulfillmentMode.pickup,
                          label: Text('Retrait'),
                          icon: Icon(Icons.shopping_bag_outlined, size: 16),
                        ),
                      if (deliveryOptionEnabled)
                        const ButtonSegment<RetailFulfillmentMode>(
                          value: RetailFulfillmentMode.delivery,
                          label: Text('Livraison'),
                          icon: Icon(Icons.local_shipping_outlined, size: 16),
                        ),
                    ],
                    selected: {fulfillment},
                    onSelectionChanged: (s) => onFulfillmentChanged(s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.nearBlack;
                        }
                        return isDark ? AppColors.coolGray : AppColors.darkGray;
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.amber;
                        }
                        return Colors.transparent;
                      }),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppConstants.animFast,
                    child: fulfillment == RetailFulfillmentMode.delivery
                        ? Padding(
                            key: const ValueKey('del'),
                            padding: const EdgeInsets.only(
                              top: AppConstants.spacing12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppInput(
                                  key: const Key('checkout-delivery-place'),
                                  label: 'Lieu *',
                                  controller: deliveryLocationCtrl,
                                  prefixIcon: Icons.place_outlined,
                                ),
                                const SizedBox(height: AppConstants.spacing8),
                                AppInput(
                                  label: 'Frais de livraison (HTG)',
                                  controller: deliveryFeeCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters:
                                      InputFormatters.decimalAmount,
                                  prefixIcon: Icons.local_shipping_outlined,
                                  onChanged: onDeliveryFeeChanged,
                                ),
                              ],
                            ),
                          )
                        : SizedBox(key: ValueKey(fulfillment)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: AppButton(
            label: 'Suivant',
            onPressed: onNext,
            icon: Icons.arrow_forward_rounded,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _SelectedClientCard extends StatelessWidget {
  final String name;
  final String phone;
  final VoidCallback onClear;

  const _SelectedClientCard({
    required this.name,
    required this.phone,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Container(
      key: const Key('checkout-selected-client'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE4E0D8),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 22, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.body(color: ink).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (phone.isNotEmpty)
                  Text(phone, style: AppTextStyles.caption(color: muted)),
              ],
            ),
          ),
          IconButton(
            key: const Key('checkout-client-clear'),
            tooltip: 'Retirer le client',
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

// ─── Review ───────────────────────────────────────────────────────────────────

class _ReviewStep extends ConsumerWidget {
  final List<RetailCartEntry> lines;
  final double discountPercent;
  final double subtotal;
  final double discountAmt;
  final double taxable;
  final double tax;
  final double gratuity;
  final double total;
  final String clientName;
  final String linkedClientPhone;
  final RetailFulfillmentMode fulfillment;
  final bool showFulfillmentChip;
  final String deliveryLocation;
  final String deliveryPhone;
  final double deliveryFee;
  final bool showDeliveryFeeRow;
  final bool isDark;
  final bool isQuote;

  /// True when editing an existing draft quote (label becomes "Mettre à jour le devis").
  final bool isUpdatingQuote;
  final VoidCallback onPay;
  final VoidCallback onSaveQuote;

  const _ReviewStep({
    required this.lines,
    required this.discountPercent,
    required this.subtotal,
    required this.discountAmt,
    required this.taxable,
    required this.tax,
    required this.gratuity,
    required this.total,
    required this.clientName,
    required this.linkedClientPhone,
    required this.fulfillment,
    required this.showFulfillmentChip,
    required this.deliveryLocation,
    required this.deliveryPhone,
    required this.deliveryFee,
    required this.showDeliveryFeeRow,
    required this.isDark,
    required this.isQuote,
    required this.isUpdatingQuote,
    required this.onPay,
    required this.onSaveQuote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = isDark ? AppColors.darkBackground : AppColors.white;
    final hasContext =
        clientName.isNotEmpty ||
        linkedClientPhone.isNotEmpty ||
        showFulfillmentChip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Mini context banner ──────────────────────────────────────
        if (hasContext)
          Container(
            color: isDark
                ? AppColors.primaryBlue.withValues(alpha: 0.15)
                : AppColors.lightBlue,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing12,
              vertical: 6,
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (clientName.isNotEmpty)
                  _ContextChip(
                    icon: Icons.person_outline,
                    label: clientName,
                    isDark: isDark,
                  ),
                if (showFulfillmentChip)
                  _ContextChip(
                    icon: Icons.local_mall_outlined,
                    label: fulfillment.label,
                    isDark: isDark,
                    accent: fulfillment == RetailFulfillmentMode.delivery,
                  ),
                if (linkedClientPhone.isNotEmpty)
                  _ContextChip(
                    icon: Icons.phone_outlined,
                    label: linkedClientPhone,
                    isDark: isDark,
                  ),
                if (fulfillment == RetailFulfillmentMode.delivery &&
                    deliveryLocation.isNotEmpty)
                  _ContextChip(
                    icon: Icons.place_outlined,
                    label: deliveryLocation,
                    isDark: isDark,
                    accent: true,
                  ),
              ],
            ),
          ),
        // ── Scrollable order table ───────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacing12,
              AppConstants.spacing12,
              AppConstants.spacing12,
              AppConstants.spacing8,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppConstants.spacing12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFE8E8E8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tableHeader(isDark),
                  const Divider(height: AppConstants.spacing16),
                  ...lines.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppConstants.spacing8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${e.quantity}',
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.lineLabel,
                              style: AppTextStyles.body(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Text(
                              CurrencyFormatter.amountOnly(e.unitPriceHtg),
                              textAlign: TextAlign.right,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Text(
                              CurrencyFormatter.amountOnly(
                                e.unitPriceHtg * e.quantity,
                              ),
                              textAlign: TextAlign.right,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: AppConstants.spacing16),
                  _moneyRow(context, 'Sous-total', subtotal, isDark),
                  if (discountPercent > 0)
                    _moneyRow(
                      context,
                      'Remise (${discountPercent.toStringAsFixed(0)} %)',
                      -discountAmt,
                      isDark,
                    ),
                  if (ref.watch(taxEnabledProvider))
                    _moneyRow(context, 'Tax', tax, isDark),
                  if (ref.watch(gratuityEnabledProvider))
                    _moneyRow(context, 'Frais de service', gratuity, isDark),
                  if (showDeliveryFeeRow)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppConstants.spacing4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Frais de livraison',
                            style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                          Text(
                            deliveryFee > 0
                                ? CurrencyFormatter.local(context, deliveryFee)
                                : 'Free',
                            style: AppTextStyles.body(
                              color: deliveryFee > 0
                                  ? (isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack)
                                  : AppColors.deepGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppConstants.spacing8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppTextStyles.h3(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.local(context, total),
                        style: AppTextStyles.price(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Sticky action buttons ────────────────────────────────────
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isQuote) ...[
                AppButton(
                  label: isUpdatingQuote
                      ? 'Mettre à jour le devis'
                      : 'Enregistrer comme devis',
                  onPressed: onSaveQuote,
                  icon: Icons.request_quote_outlined,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                ),
                const SizedBox(height: 4),
              ],
              AppButton(
                label: 'Payer',
                onPressed: onPay,
                icon: Icons.payment_rounded,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(bool isDark) {
    final headerColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text('Qté', style: AppTextStyles.caption(color: headerColor)),
        ),
        Expanded(
          child: Text(
            'Article',
            style: AppTextStyles.caption(color: headerColor),
          ),
        ),
        SizedBox(
          width: 88,
          child: Text(
            'Unité',
            textAlign: TextAlign.right,
            style: AppTextStyles.caption(color: headerColor),
          ),
        ),
        SizedBox(
          width: 88,
          child: Text(
            'Total',
            textAlign: TextAlign.right,
            style: AppTextStyles.caption(color: headerColor),
          ),
        ),
      ],
    );
  }

  Widget _moneyRow(
    BuildContext context,
    String label,
    double amount,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
          ),
          Text(
            CurrencyFormatter.local(context, amount),
            style: AppTextStyles.body(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small icon+label chip used in the review step context banner.
class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool accent;

  const _ContextChip({
    required this.icon,
    required this.label,
    required this.isDark,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.amber
        : (isDark ? AppColors.coolGray : AppColors.darkGray);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: AppTextStyles.caption(color: color)),
      ],
    );
  }
}

// ─── Payment (from POS) ───────────────────────────────────────────────────────

class _RetailPaymentPanel extends ConsumerStatefulWidget {
  final double total;
  final String checkoutId;
  final String knownClientName;
  final String knownClientPhone;
  final bool clientFromDirectory;
  final bool submitting;
  final Future<bool> Function() onValidateStock;
  final Future<void> Function(
    PaymentMethodType method, {
    RetailCheckPayment? check,
    double? amountPaidHtg,
    double balanceDueHtg,
    Customer? creditCustomer,
    String? creditAuthorizedBy,
  }) onConfirm;

  const _RetailPaymentPanel({
    required this.total,
    required this.checkoutId,
    required this.knownClientName,
    required this.knownClientPhone,
    required this.clientFromDirectory,
    required this.submitting,
    required this.onValidateStock,
    required this.onConfirm,
  });

  @override
  ConsumerState<_RetailPaymentPanel> createState() =>
      _RetailPaymentPanelState();
}

class _RetailPaymentPanelState extends ConsumerState<_RetailPaymentPanel> {
  _RPayMethod _method = _RPayMethod.cash;
  _CardEntry _cardEntry = _CardEntry.form;
  final PaymentsClient _payments = PaymentsClient();
  final StripeCardController _cardController = StripeCardController();
  Timer? _poll;
  bool _remoteBusy = false;
  bool _saleCompleted = false;
  String? _remoteError;
  bool _cardPaid = false;
  bool _moncashPaid = false;
  String? _moncashUrl;
  String? _moncashOrderId;
  bool _cardConfigLoading = false;
  bool _cardConfigLoaded = false;
  String? _publishableKey;
  String? _cardConfigError;
  String? _shareUrl;
  String? _shareSessionId;
  bool _linkCopied = false;
  final _payerNameCtrl = TextEditingController();
  final _payerContactCtrl = TextEditingController();

  // Cash
  double _cashReceived = 0;
  final _cashCtrl = TextEditingController();
  final _balancePhoneCtrl = TextEditingController();

  // Credit
  Customer? _selectedCustomer;
  String _creditSearch = '';
  double _creditPartialPaid = 0;
  bool _showNewCustomer = false;
  final _newNameCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _partialCtrl = TextEditingController();

  // Check
  final _checkNumberCtrl = TextEditingController();
  final _checkBankCtrl = TextEditingController();
  final _checkPayerCtrl = TextEditingController();
  DateTime _checkDate = DateTime.now();
  Uint8List? _checkPhoto;
  String _checkMime = 'image/jpeg';
  String? _checkPhotoError;
  bool _checkPhotoBusy = false;
  bool _clearCheckNow = false;

  @override
  void initState() {
    super.initState();
    _balancePhoneCtrl.addListener(_onBalancePhone);
    if (_isDirectoryClient) {
      _selectedCustomer = _clientAsCreditCustomer();
    }
  }

  Customer _clientAsCreditCustomer() {
    final name = widget.knownClientName.trim();
    final phone = widget.knownClientPhone.trim();
    final match = _directoryMatch;
    if (match == null) {
      return Customer(
        id: 'known_${phone.replaceAll(RegExp(r'\D'), '')}',
        name: name,
        phone: phone,
        createdAt: DateTime.now(),
      );
    }
    return Customer(
      id: match.id,
      name: name,
      phone: phone,
      isCreditBlocked: match.isCreditBlocked,
      blockedReason: match.blockedReason,
      blockedBy: match.blockedBy,
      blockedAt: match.blockedAt,
      creditLimitHtg: match.creditLimitHtg,
      creditLimitUsd: match.creditLimitUsd,
      createdAt: match.createdAt,
      isActive: match.isActive,
    );
  }

  Customer _resolveCreditCustomer(Customer customer) {
    final customers = ref.read(customerProvider).customers;
    for (final existing in customers) {
      if (existing.id == customer.id) return existing;
    }
    return _creditCustomerByPhone(customers, customer.phone) ?? customer;
  }

  void _onBalancePhone() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cardController.detach();
    _payments.close();
    _balancePhoneCtrl.removeListener(_onBalancePhone);
    _balancePhoneCtrl.dispose();
    _cashCtrl.dispose();
    _newNameCtrl.dispose();
    _newPhoneCtrl.dispose();
    _partialCtrl.dispose();
    _payerNameCtrl.dispose();
    _payerContactCtrl.dispose();
    _checkNumberCtrl.dispose();
    _checkBankCtrl.dispose();
    _checkPayerCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (widget.submitting || _remoteBusy || _saleCompleted) return false;
    if (_method == _RPayMethod.credit) {
      return _selectedCustomer != null && !_selectedCustomer!.isCreditBlocked;
    }
    if (_method == _RPayMethod.moncash && !_moncashPaid) {
      if (_moncashUrl != null && _moncashUrl!.trim().isNotEmpty) return true;
      return widget.total.round() >= 1;
    }
    if (_method == _RPayMethod.card && !_cardPaid) {
      if (_cardPricing() == null) return false;
      if (_cardEntry == _CardEntry.form) return _cardController.isReady;
      if (_shareUrl != null) return false;
      return _payerNameCtrl.text.trim().isNotEmpty &&
          _payerContactCtrl.text.trim().isNotEmpty;
    }
    if (_method == _RPayMethod.check) {
      return _builtCheck() != null;
    }
    if (_method == _RPayMethod.cash && _cashBalanceDue > 0.009) {
      if (_isDirectoryClient) {
        final match = _directoryMatch;
        if (match == null) return true;
        if (match.isCreditBlocked) return false;
        if (_creditWouldExceed(match, _cashBalanceDue)) return false;
        return true;
      }
      if (_isPhoneOnlyClient) {
        return widget.knownClientPhone.trim().isNotEmpty ||
            _balancePhoneCtrl.text.trim().isNotEmpty;
      }
      final customer = _selectedCustomer;
      if (customer == null || customer.isCreditBlocked) return false;
      if (_creditWouldExceed(customer, _cashBalanceDue)) return false;
    }
    return true;
  }

  bool get _isDirectoryClient =>
      widget.clientFromDirectory &&
      widget.knownClientName.trim().isNotEmpty &&
      widget.knownClientPhone.trim().isNotEmpty;

  bool get _isPhoneOnlyClient =>
      widget.knownClientName.trim().isNotEmpty && !_isDirectoryClient;

  Customer? get _directoryMatch {
    if (!_isDirectoryClient) return null;
    return _creditCustomerByPhone(
      ref.read(customerProvider).customers,
      widget.knownClientPhone,
    );
  }

  bool get _cashAmountEntered => _cashCtrl.text.trim().isNotEmpty;

  /// Empty tender is still a full cash payment. A typed amount below the
  /// total is the only partial payment.
  double get _cashBalanceDue {
    if (!_cashAmountEntered) return 0;
    final due = widget.total - _cashReceived;
    return due > 0.009 ? due : 0;
  }

  double get _cashApplied {
    if (_cashBalanceDue <= 0.009) return widget.total;
    final received = _cashReceived;
    return received < 0 ? 0 : received;
  }

  bool _creditWouldExceed(Customer customer, double amount) {
    final limit = customer.creditLimitHtg;
    if (limit == null) return false;
    final balance = ref.read(customerProvider).balanceFor(customer.id);
    return balance + amount > limit + 0.009;
  }

  String get _confirmLabel {
    if (widget.submitting || _remoteBusy) return 'Traitement…';
    if (_method == _RPayMethod.card && !_cardPaid) {
      if (_cardEntry == _CardEntry.link) {
        return _shareUrl == null ? 'Créer le lien' : 'En attente du paiement…';
      }
      final pricing = _cardPricing();
      if (pricing == null) return 'Payer par carte';
      return 'Payer ${CurrencyFormatter.usd(pricing.totalUsd)}';
    }
    if (_method == _RPayMethod.moncash && !_moncashPaid) {
      return 'Payer ${CurrencyFormatter.local(context, widget.total)}';
    }
    if (_method == _RPayMethod.check) {
      return _clearCheckNow
          ? 'Compenser le chèque'
          : 'Enregistrer le chèque';
    }
    return 'Confirmer le paiement';
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    if (_method == _RPayMethod.card && !_cardPaid) {
      if (_cardEntry == _CardEntry.link) {
        await _createShareLink();
      } else {
        await _payByCard();
      }
      return;
    }
    if (_method == _RPayMethod.moncash && !_moncashPaid) {
      final url = _moncashUrl?.trim() ?? '';
      if (url.isNotEmpty) {
        openPaymentUrl(url);
        return;
      }
      await _startMoncash();
      return;
    }
    if (!await widget.onValidateStock()) return;
    final check = _method == _RPayMethod.check ? _builtCheck() : null;
    if (_method == _RPayMethod.check && check == null) return;
    final partialCash =
        _method == _RPayMethod.cash && _cashBalanceDue > 0.009;
    final creditCustomerSelected = _method == _RPayMethod.credit
        ? (_selectedCustomer == null
            ? null
            : _resolveCreditCustomer(_selectedCustomer!))
        : null;
    final creditAmount = creditCustomerSelected == null
        ? 0.0
        : widget.total - _creditPartialPaid;
    if (creditAmount > 0.009 && creditCustomerSelected != null) {
      final state = ref.read(customerProvider);
      final balance = state.balanceFor(creditCustomerSelected.id);
      final limit = creditCustomerSelected.creditLimitHtg;
      if (limit != null && (balance + creditAmount) > limit) return;
    }
    String? authorizedBy;
    if (partialCash || creditAmount > 0.009) {
      final granted = await _authorizeClientCredit();
      if (!granted || !mounted) return;
      authorizedBy = _creditAuthorizedBy;
    }
    if (creditAmount > 0.009 && creditCustomerSelected != null) {
      final note = authorizedBy == null
          ? 'Vente au détail'
          : 'Vente au détail · Autorisé par $authorizedBy';
      final alreadyKnown = ref
          .read(customerProvider)
          .customers
          .any((customer) => customer.id == creditCustomerSelected.id);
      if (!alreadyKnown) {
        ref.read(customerProvider.notifier).addCustomer(creditCustomerSelected);
      }
      ref.read(customerProvider.notifier).postCharge(
            customerId: creditCustomerSelected.id,
            amountHtg: widget.total,
            paidAmountHtg: _creditPartialPaid,
            cashierName: 'Caissier',
            description: note,
          );
    }
    final balanceCustomer =
        partialCash ? _ensureBalanceCustomer() : null;
    if (partialCash && balanceCustomer == null) return;
    await _finishSale(
      switch (_method) {
        _RPayMethod.moncash => PaymentMethodType.moncash,
        _RPayMethod.card => PaymentMethodType.card,
        _RPayMethod.cash => PaymentMethodType.cash,
        _RPayMethod.credit => PaymentMethodType.credit,
        _RPayMethod.check => PaymentMethodType.check,
      },
      check: check,
      amountPaidHtg: partialCash ? _cashApplied : null,
      balanceDueHtg: partialCash ? _cashBalanceDue : 0,
      creditCustomer: balanceCustomer,
      creditAuthorizedBy: authorizedBy,
    );
  }

  String? _creditAuthorizedBy;

  Future<bool> _authorizeClientCredit() async {
    _creditAuthorizedBy = null;
    final auth = ref.read(authProvider);
    final allowed = currentUserCanGrantClientCredit(
      session: ref.read(staffSessionProvider),
      shopAccountSignedIn: auth.status == AuthStatus.authenticated,
      module: auth.module,
      settings: ref.read(permissionSettingsProvider),
    );
    if (allowed) return true;
    final name = await showCreditGrantPinDialog(
      context,
      ref,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
    if (name == null) return false;
    _creditAuthorizedBy = name;
    return true;
  }

  Customer? _ensureBalanceCustomer() {
    if (_isDirectoryClient) {
      final match = _directoryMatch;
      if (match != null) return match;
      final created = Customer(
        id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
        name: widget.knownClientName.trim(),
        phone: widget.knownClientPhone.trim(),
        createdAt: DateTime.now(),
      );
      ref.read(customerProvider.notifier).addCustomer(created);
      return created;
    }
    if (_isPhoneOnlyClient) {
      final known = widget.knownClientPhone.trim();
      final phone = known.isNotEmpty ? known : _balancePhoneCtrl.text.trim();
      if (phone.isEmpty) return null;
      final created = Customer(
        id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
        name: widget.knownClientName.trim(),
        phone: phone,
        createdAt: DateTime.now(),
      );
      ref.read(customerProvider.notifier).addCustomer(created);
      return created;
    }
    return _selectedCustomer;
  }

  RetailCheckPayment? _builtCheck() {
    return RetailCheckPayment.compose(
      number: _checkNumberCtrl.text,
      bank: _checkBankCtrl.text,
      payerName: _checkPayerCtrl.text,
      date: _checkDate,
      photo: _checkPhoto,
      mime: _checkMime,
      cleared: _clearCheckNow,
      clearedAt: _clearCheckNow ? DateTime.now() : null,
      clearedBy: _clearCheckNow ? _operatorName() : null,
    );
  }

  String _operatorName() {
    return currentOperatorName(
      staffName: ref.read(staffSessionProvider)?.employeeName,
      accountName: ref.read(authProvider).userName,
    );
  }

  Future<void> _pickCheckPhoto() async {
    setState(() {
      _checkPhotoBusy = true;
      _checkPhotoError = null;
    });
    PickedProductPhoto? picked;
    var failed = false;
    try {
      picked = await checkPhotoPicker();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _checkPhotoBusy = false;
      if (failed) {
        _checkPhotoError = 'La photo n\'a pas pu être ajoutée. Réessayez.';
        return;
      }
      if (picked == null) return;
      if (picked.error != null && picked.error!.isNotEmpty) {
        _checkPhotoError = picked.error;
        return;
      }
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        _checkPhotoError = 'La photo du chèque est illisible.';
        return;
      }
      _checkPhoto = bytes;
      _checkMime = picked.mime;
      _checkPhotoError = null;
    });
  }

  Future<void> _finishSale(
    PaymentMethodType method, {
    RetailCheckPayment? check,
    double? amountPaidHtg,
    double balanceDueHtg = 0,
    Customer? creditCustomer,
    String? creditAuthorizedBy,
  }) async {
    if (_saleCompleted) return;
    _saleCompleted = true;
    _poll?.cancel();
    await widget.onConfirm(
      method,
      check: check,
      amountPaidHtg: amountPaidHtg,
      balanceDueHtg: balanceDueHtg,
      creditCustomer: creditCustomer,
      creditAuthorizedBy: creditAuthorizedBy,
    );
  }

  CardChargePricing? _cardPricing() {
    final rate = ref.read(currencySettingsProvider).usdToLocalRate;
    final cents = CardChargePricing.htgToUsdCents(widget.total, rate);
    if (cents <= 0) return null;
    return CardChargePricing.fromOrderUsdCents(cents);
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

  void _selectMethod(_RPayMethod method) {
    _poll?.cancel();
    setState(() {
      _method = method;
      _remoteError = null;
    });
    if (method == _RPayMethod.card) {
      _loadCardConfig();
      _resumeSharePoll();
    } else if (method == _RPayMethod.moncash) {
      if (_moncashPaid) return;
      if (_moncashUrl != null && _moncashUrl!.trim().isNotEmpty) {
        _resumeMoncashPoll();
      } else if (!_remoteBusy) {
        _startMoncash();
      }
    }
  }

  void _selectCardEntry(_CardEntry entry) {
    if (_shareUrl != null || _cardPaid || _remoteBusy) return;
    if (_cardEntry == entry) return;
    setState(() {
      _cardEntry = entry;
      _remoteError = null;
    });
  }

  Future<bool> _intentPaidSoon(String intentId) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (await _payments.cardIntentPaid(intentId)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

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
        reference: widget.checkoutId,
        orderUsdCents: pricing.orderUsdCents,
        description: 'Vente ${widget.checkoutId}',
      );
      if (!mounted || _method != _RPayMethod.card) {
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
      if (!await widget.onValidateStock()) return;
      await _finishSale(PaymentMethodType.card);
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
        reference: widget.checkoutId,
        orderUsdCents: pricing.orderUsdCents,
        description: 'Vente ${widget.checkoutId}',
        recipientName: name,
        recipientEmail: email,
        recipientPhone: email.isEmpty ? contact : '',
      );
      if (!mounted || _method != _RPayMethod.card) {
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
        if (!mounted || _cardPaid) return;
        setState(() => _cardPaid = true);
        if (!await widget.onValidateStock()) return;
        await _finishSale(PaymentMethodType.card);
      },
    );
  }

  void _resumeSharePoll() {
    final id = _shareSessionId;
    if (id == null || _cardPaid || _method != _RPayMethod.card) return;
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
      setState(
        () => _remoteError = 'Le partage a échoué. Copiez le lien.',
      );
    }
  }

  Future<void> _startMoncash() async {
    final amount = widget.total.round();
    if (amount < 1) {
      setState(
        () => _remoteError = 'Le montant MonCash doit être d\'au moins 1 HTG.',
      );
      return;
    }
    _poll?.cancel();
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    try {
      final payment = await _payments.createMoncash(
        orderId: widget.checkoutId,
        amountHtg: amount,
      );
      if (!mounted || _method != _RPayMethod.moncash) {
        if (mounted) setState(() => _remoteBusy = false);
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
        if (!mounted || _moncashPaid) return;
        setState(() => _moncashPaid = true);
        if (!await widget.onValidateStock()) return;
        await _finishSale(PaymentMethodType.moncash);
      },
    );
  }

  void _resumeMoncashPoll() {
    final id = _moncashOrderId;
    if (id == null || _moncashPaid || _method != _RPayMethod.moncash) return;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customerState = ref.watch(customerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Total :', style: AppTextStyles.body()),
                  const SizedBox(width: 6),
                  Text(
                    CurrencyFormatter.local(context, widget.total),
                    style: AppTextStyles.price(),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'ID: ${widget.checkoutId}',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ],
          ),
        ),
        // ── Method tabs ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RetailMethodTab(
                label: 'Espèces',
                icon: Icons.payments_outlined,
                selected: _method == _RPayMethod.cash,
                onTap: () => _selectMethod(_RPayMethod.cash),
              ),
              _RetailMethodTab(
                label: 'Chèque',
                icon: Icons.account_balance_outlined,
                selected: _method == _RPayMethod.check,
                onTap: () => _selectMethod(_RPayMethod.check),
              ),
              _RetailMethodTab(
                label: 'MonCash',
                icon: Icons.phone_android_outlined,
                selected: _method == _RPayMethod.moncash,
                onTap: () => _selectMethod(_RPayMethod.moncash),
              ),
              _RetailMethodTab(
                label: 'Carte',
                icon: Icons.credit_card_outlined,
                selected: _method == _RPayMethod.card,
                onTap: () => _selectMethod(_RPayMethod.card),
              ),
              _RetailMethodTab(
                label: 'Crédit',
                icon: Icons.account_balance_wallet_outlined,
                selected: _method == _RPayMethod.credit,
                onTap: () => _selectMethod(_RPayMethod.credit),
                accentColor: AppColors.amber,
              ),
            ],
          ),
        ),
        // ── Method content ────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: AnimatedSwitcher(
              duration: AppConstants.animFast,
              child: KeyedSubtree(
                key: ValueKey(_method),
                child: _buildMethodContent(isDark, customerState),
              ),
            ),
          ),
        ),
        // ── Confirm button ────────────────────────────────────────────
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: AppButton(
            label: _confirmLabel,
            onPressed: _canConfirm ? _confirm : null,
            isLoading: widget.submitting || _remoteBusy,
            icon: _method == _RPayMethod.card && !_cardPaid
                ? (_cardEntry == _CardEntry.link
                      ? Icons.link
                      : Icons.credit_card_outlined)
                : _method == _RPayMethod.moncash && !_moncashPaid
                ? Icons.open_in_new
                : Icons.check_circle_outline,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodContent(bool isDark, CustomerState customerState) {
    switch (_method) {
      case _RPayMethod.moncash:
        return _RMonCashContent(
          totalHtg: widget.total,
          isDark: isDark,
          error: _remoteError,
          preparing: _remoteBusy && (_moncashUrl == null || _moncashUrl!.trim().isEmpty),
          waiting: (_poll?.isActive ?? false) && !_moncashPaid,
          paid: _moncashPaid,
          paymentUrl: _moncashUrl,
        );
      case _RPayMethod.card:
        return _RCardContent(
          isDark: isDark,
          pricing: _cardPricing(),
          orderLocalLabel: CurrencyFormatter.local(context, widget.total),
          error: _remoteError,
          waiting: _remoteBusy || ((_poll?.isActive ?? false) && !_cardPaid),
          paid: _cardPaid,
          entry: _cardEntry,
          entryLocked: _shareUrl != null || _cardPaid || _remoteBusy,
          onEntry: _selectCardEntry,
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
      case _RPayMethod.cash:
        {
        final balanceCustomer = _selectedCustomer;
        final balanceExceeds = balanceCustomer != null &&
            _creditWouldExceed(balanceCustomer, _cashBalanceDue);
        final directoryMatch = _directoryMatch;
        return _RCashContent(
          totalHtg: widget.total,
          cashReceived: _cashReceived,
          balanceDue: _cashBalanceDue,
          cashCtrl: _cashCtrl,
          isDark: isDark,
          knownClientName: widget.knownClientName,
          knownClientPhone: widget.knownClientPhone,
          phoneOnly: _isPhoneOnlyClient,
          directoryClient: _isDirectoryClient,
          directoryMatch: directoryMatch,
          balancePhoneCtrl: _balancePhoneCtrl,
          directoryBlocked: directoryMatch?.isCreditBlocked ?? false,
          directoryExceedsLimit: directoryMatch != null &&
              _creditWouldExceed(directoryMatch, _cashBalanceDue),
          onCashChanged: (v) =>
              setState(() => _cashReceived = double.tryParse(v) ?? 0),
          onQuickCash: (amt) {
            _cashCtrl.text = amt.toStringAsFixed(0);
            setState(() => _cashReceived = amt);
          },
          selectedCustomer: _selectedCustomer,
          creditSearch: _creditSearch,
          showNewCustomer: _showNewCustomer,
          newNameCtrl: _newNameCtrl,
          newPhoneCtrl: _newPhoneCtrl,
          customerState: customerState,
          balanceExceedsLimit: balanceExceeds,
          onSearchChanged: (v) => setState(() => _creditSearch = v),
          onCustomerSelected: (c) => setState(() {
            _selectedCustomer = c;
            _creditSearch = '';
          }),
          onCustomerCleared: () => setState(() => _selectedCustomer = null),
          onToggleNewForm: () =>
              setState(() => _showNewCustomer = !_showNewCustomer),
          onCustomerCreated: (c) {
            ref.read(customerProvider.notifier).addCustomer(c);
            _newNameCtrl.clear();
            _newPhoneCtrl.clear();
            setState(() {
              _selectedCustomer = c;
              _showNewCustomer = false;
              _creditSearch = '';
            });
          },
        );
        }
      case _RPayMethod.credit:
        return _RCreditContent(
          totalHtg: widget.total,
          isDark: isDark,
          selectedCustomer: _selectedCustomer,
          creditSearch: _creditSearch,
          creditPartialPaid: _creditPartialPaid,
          showNewCustomer: _showNewCustomer,
          newNameCtrl: _newNameCtrl,
          newPhoneCtrl: _newPhoneCtrl,
          partialCtrl: _partialCtrl,
          customerState: customerState,
          onSearchChanged: (v) => setState(() => _creditSearch = v),
          onCustomerSelected: (c) => setState(() {
            _selectedCustomer = c;
            _creditSearch = '';
          }),
          onCustomerCleared: () => setState(() {
            _selectedCustomer = null;
            _creditSearch = '';
            _showNewCustomer = false;
          }),
          onPartialChanged: (v) =>
              setState(() => _creditPartialPaid = double.tryParse(v) ?? 0),
          onToggleNewForm: () =>
              setState(() => _showNewCustomer = !_showNewCustomer),
          onCustomerCreated: (c) {
            ref.read(customerProvider.notifier).addCustomer(c);
            setState(() {
              _selectedCustomer = c;
              _showNewCustomer = false;
            });
          },
        );
      case _RPayMethod.check:
        return CheckPaymentForm(
          totalHtg: widget.total,
          isDark: isDark,
          numberCtrl: _checkNumberCtrl,
          bankCtrl: _checkBankCtrl,
          payerCtrl: _checkPayerCtrl,
          date: _checkDate,
          photo: _checkPhoto,
          photoError: _checkPhotoError,
          picking: _checkPhotoBusy,
          clearNow: _clearCheckNow,
          onChanged: (_) => setState(() {}),
          onDate: (value) => setState(() => _checkDate = value),
          onClearNow: (value) => setState(() => _clearCheckNow = value),
          onPickPhoto: _pickCheckPhoto,
        );
    }
  }
}

// ─── Payment method enum ──────────────────────────────────────────────────────

enum _RPayMethod { moncash, card, cash, credit, check }

enum _CardEntry { form, link }

// ─── Method tab ───────────────────────────────────────────────────────────────

class _RetailMethodTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? accentColor;

  const _RetailMethodTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        accentColor ?? (isDark ? AppColors.skyBlue : AppColors.primaryBlue);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : (isDark ? AppColors.darkSurface : AppColors.white),
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          border: Border.all(
            color: selected
                ? accent
                : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? (accentColor != null
                        ? AppColors.nearBlack
                        : AppColors.white)
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption(
                color: selected
                    ? (accentColor != null
                          ? AppColors.nearBlack
                          : AppColors.white)
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MonCash content ──────────────────────────────────────────────────────────

class _RMonCashContent extends StatelessWidget {
  final double totalHtg;
  final bool isDark;
  final String? error;
  final bool preparing;
  final bool waiting;
  final bool paid;
  final String? paymentUrl;

  const _RMonCashContent({
    required this.totalHtg,
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
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.phone_android_outlined,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Text('Paiement MonCash', style: AppTextStyles.h3()),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
              Text(
                url.isEmpty
                    ? 'Préparation du code pour le téléphone du client. '
                          'Les frais MonCash restent ceux de Digicel.'
                    : 'Le client scanne ce code avec son téléphone. '
                          'Payer ouvre MonCash sur cet appareil. '
                          'Les frais MonCash restent ceux de Digicel.',
                style: AppTextStyles.body(color: muted),
              ),
              const SizedBox(height: AppConstants.spacing12),
              Text(
                CurrencyFormatter.local(context, totalHtg),
                style: AppTextStyles.price(),
              ),
              if (preparing) ...[
                const SizedBox(height: AppConstants.spacing16),
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
              if (url.isNotEmpty) ...[
                const SizedBox(height: AppConstants.spacing12),
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
          ),
        ),
      ),
    );
  }
}

// ─── Card content ─────────────────────────────────────────────────────────────

class _RCardContent extends StatelessWidget {
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

  const _RCardContent({
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
    final accent = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final key = publishableKey?.trim() ?? '';
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                  Row(
                    children: [
                      Icon(Icons.credit_card_outlined, color: accent),
                      const SizedBox(width: 8),
                      Text('Paiement par carte', style: AppTextStyles.h3()),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                  Row(
                    children: [
                      Expanded(
                        child: _CardPathButton(
                          label: 'Par carte',
                          icon: Icons.credit_card_outlined,
                          selected: entry == _CardEntry.form,
                          onTap: entryLocked
                              ? null
                              : () => onEntry(_CardEntry.form),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CardPathButton(
                          label: 'Lien de paiement',
                          icon: Icons.link,
                          selected: entry == _CardEntry.link,
                          onTap: entryLocked
                              ? null
                              : () => onEntry(_CardEntry.link),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                  Text(
                    entry == _CardEntry.form
                        ? 'Saisissez la carte ici. Elle est envoyée à Stripe, pas à la caisse.'
                        : 'Créez un lien à partager. La vente est enregistrée quand le client a payé.',
                    style: AppTextStyles.body(color: muted),
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                  if (pricing == null)
                    Text(
                      'Taux de change indisponible.',
                      style: AppTextStyles.body(color: AppColors.boldRed),
                    )
                  else
                    CardFeeBreakdown(
                      pricing: pricing!,
                      isDark: isDark,
                      orderLocalLabel: orderLocalLabel,
                    ),
                  if (entry == _CardEntry.link) ...[
                    const SizedBox(height: AppConstants.spacing12),
                    if (shareUrl == null) ...[
                      AppInput(
                        label: 'Nom du payeur',
                        controller: payerNameCtrl,
                        onChanged: (_) => onPayerChanged(),
                      ),
                      const SizedBox(height: AppConstants.spacing8),
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
                      (configError != null && configError!.isNotEmpty)) ...[
                    const SizedBox(height: AppConstants.spacing8),
                    Text(
                      configError!,
                      style: AppTextStyles.body(color: AppColors.boldRed),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spacing8),
                  Text(
                    'Propulsé par Stripe',
                    style: AppTextStyles.caption(color: muted),
                  ),
                  if (entry == _CardEntry.form) ...[
                    const SizedBox(height: 8),
                    if (configLoading || key.isEmpty)
                      SizedBox(
                        height: 44,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            configLoading
                                ? 'Chargement du formulaire…'
                                : (configError ??
                                      'Formulaire carte indisponible.'),
                            style: AppTextStyles.caption(
                              color: configError == null
                                  ? muted
                                  : AppColors.boldRed,
                            ),
                          ),
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
              ),
            ),
          ),
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
    final enabled = onTap != null || selected;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
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
        child: Text(
          error!,
          style: AppTextStyles.body(color: AppColors.boldRed),
        ),
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

// ─── Cash content ─────────────────────────────────────────────────────────────

class _RCashContent extends StatelessWidget {
  final double totalHtg;
  final double cashReceived;
  final double balanceDue;
  final TextEditingController cashCtrl;
  final bool isDark;
  final String knownClientName;
  final String knownClientPhone;
  final bool phoneOnly;
  final bool directoryClient;
  final Customer? directoryMatch;
  final TextEditingController balancePhoneCtrl;
  final bool directoryBlocked;
  final bool directoryExceedsLimit;
  final ValueChanged<String> onCashChanged;
  final ValueChanged<double> onQuickCash;
  final Customer? selectedCustomer;
  final String creditSearch;
  final bool showNewCustomer;
  final TextEditingController newNameCtrl;
  final TextEditingController newPhoneCtrl;
  final CustomerState customerState;
  final bool balanceExceedsLimit;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onCustomerSelected;
  final VoidCallback onCustomerCleared;
  final VoidCallback onToggleNewForm;
  final ValueChanged<Customer> onCustomerCreated;

  const _RCashContent({
    required this.totalHtg,
    required this.cashReceived,
    required this.balanceDue,
    required this.cashCtrl,
    required this.isDark,
    required this.knownClientName,
    required this.knownClientPhone,
    required this.phoneOnly,
    required this.directoryClient,
    required this.directoryMatch,
    required this.balancePhoneCtrl,
    required this.directoryBlocked,
    required this.directoryExceedsLimit,
    required this.onCashChanged,
    required this.onQuickCash,
    required this.selectedCustomer,
    required this.creditSearch,
    required this.showNewCustomer,
    required this.newNameCtrl,
    required this.newPhoneCtrl,
    required this.customerState,
    required this.balanceExceedsLimit,
    required this.onSearchChanged,
    required this.onCustomerSelected,
    required this.onCustomerCleared,
    required this.onToggleNewForm,
    required this.onCustomerCreated,
  });

  @override
  Widget build(BuildContext context) {
    final change = cashReceived - totalHtg;
    final short = balanceDue > 0.009;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Text('Paiement en espèces', style: AppTextStyles.h3()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Montant dû', style: AppTextStyles.body()),
                Text(
                  CurrencyFormatter.local(context, totalHtg),
                  style: AppTextStyles.price(),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              key: const Key('cash-received'),
              controller: cashCtrl,
              onChanged: onCashChanged,
              decoration: InputDecoration(
                labelText: 'Espèces reçues (HTG)',
                prefixText: 'HTG ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: InputFormatters.decimalAmount,
            ),
            const SizedBox(height: AppConstants.spacing8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [500, 1000, 2000, 5000, 10000]
                  .map(
                    (amt) => ActionChip(
                      label: Text(CurrencyFormatter.compact(amt.toDouble())),
                      onPressed: () => onQuickCash(amt.toDouble()),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            if (!short && change >= 0) ...[
              const Divider(height: AppConstants.spacing16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Monnaie', style: AppTextStyles.body()),
                  Text(
                    CurrencyFormatter.local(context, change),
                    style: AppTextStyles.price(color: AppColors.deepGreen),
                  ),
                ],
              ),
            ],
            if (short) ...[
              const SizedBox(height: AppConstants.spacing12),
              Container(
                key: const Key('cash-balance-warning'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.boldRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.boldRed.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.boldRed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Montant insuffisant. Solde restant : ${CurrencyFormatter.local(context, balanceDue)}. Ajoutez le montant correct ou enregistrez-le comme crédit au client.',
                        style: AppTextStyles.body(color: AppColors.boldRed)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              if (directoryClient)
                _KnownBalanceClient(
                  name: directoryMatch?.name ?? knownClientName,
                  phone: directoryMatch?.phone ?? knownClientPhone,
                  blocked: directoryBlocked,
                  exceedsLimit: directoryExceedsLimit,
                  creating: directoryMatch == null,
                )
              else if (phoneOnly) ...[
                Text(
                  knownClientName,
                  key: const Key('cash-known-client'),
                  style: AppTextStyles.body(color: ink)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (knownClientPhone.trim().isNotEmpty)
                  Text(knownClientPhone, style: AppTextStyles.caption())
                else
                  PhoneField(
                    key: const Key('cash-balance-phone'),
                    controller: balancePhoneCtrl,
                    label: 'Téléphone *',
                  ),
              ] else
                _CashCreditPicker(
                  isDark: isDark,
                  balanceDue: balanceDue,
                  selectedCustomer: selectedCustomer,
                  creditSearch: creditSearch,
                  showNewCustomer: showNewCustomer,
                  newNameCtrl: newNameCtrl,
                  newPhoneCtrl: newPhoneCtrl,
                  customerState: customerState,
                  balanceExceedsLimit: balanceExceedsLimit,
                  onSearchChanged: onSearchChanged,
                  onCustomerSelected: onCustomerSelected,
                  onCustomerCleared: onCustomerCleared,
                  onToggleNewForm: onToggleNewForm,
                  onCustomerCreated: onCustomerCreated,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KnownBalanceClient extends StatelessWidget {
  final String name;
  final String phone;
  final bool blocked;
  final bool exceedsLimit;
  final bool creating;

  const _KnownBalanceClient({
    required this.name,
    required this.phone,
    required this.blocked,
    required this.exceedsLimit,
    required this.creating,
  });

  @override
  Widget build(BuildContext context) {
    final note = blocked
        ? '$name est bloqué.'
        : exceedsLimit
            ? 'La limite de crédit sera dépassée.'
            : creating
                ? 'Un compte sera créé pour ce client.'
                : 'Le solde sera enregistré sur ce compte.';
    final color = blocked || exceedsLimit ? AppColors.boldRed : AppColors.darkGray;
    return Column(
      key: const Key('cash-known-client'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          name,
          style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700),
        ),
        if (phone.trim().isNotEmpty)
          Text(phone, style: AppTextStyles.caption()),
        const SizedBox(height: 4),
        Text(
          note,
          key: blocked || exceedsLimit ? const Key('cash-credit-limit') : null,
          style: AppTextStyles.body(color: color).copyWith(
            fontWeight: blocked || exceedsLimit ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Customer? _creditCustomerByPhone(List<Customer> customers, String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 8) return null;
  for (final customer in customers) {
    final other = customer.phone.replaceAll(RegExp(r'\D'), '');
    if (other.length < 8) continue;
    if (other.endsWith(digits) || digits.endsWith(other)) return customer;
  }
  return null;
}

class _CashCreditPicker extends StatelessWidget {
  final bool isDark;
  final double balanceDue;
  final Customer? selectedCustomer;
  final String creditSearch;
  final bool showNewCustomer;
  final TextEditingController newNameCtrl;
  final TextEditingController newPhoneCtrl;
  final CustomerState customerState;
  final bool balanceExceedsLimit;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onCustomerSelected;
  final VoidCallback onCustomerCleared;
  final VoidCallback onToggleNewForm;
  final ValueChanged<Customer> onCustomerCreated;

  const _CashCreditPicker({
    required this.isDark,
    required this.balanceDue,
    required this.selectedCustomer,
    required this.creditSearch,
    required this.showNewCustomer,
    required this.newNameCtrl,
    required this.newPhoneCtrl,
    required this.customerState,
    required this.balanceExceedsLimit,
    required this.onSearchChanged,
    required this.onCustomerSelected,
    required this.onCustomerCleared,
    required this.onToggleNewForm,
    required this.onCustomerCreated,
  });

  @override
  Widget build(BuildContext context) {
    final results = creditSearch.trim().isEmpty
        ? <Customer>[]
        : customerState.customers
            .where(
              (c) =>
                  c.isActive &&
                  (c.name.toLowerCase().contains(creditSearch.toLowerCase()) ||
                      c.phone.contains(creditSearch)),
            )
            .toList();
    final customer = selectedCustomer;

    if (customer != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.2)
                  : AppColors.lightBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(customer.name, style: AppTextStyles.body()),
                ),
                TextButton(
                  onPressed: onCustomerCleared,
                  child: const Text('Retirer'),
                ),
              ],
            ),
          ),
          if (customer.isCreditBlocked || balanceExceedsLimit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                customer.isCreditBlocked
                    ? '${customer.name} est bloqué.'
                    : 'La limite de crédit sera dépassée.',
                key: const Key('cash-credit-limit'),
                style: AppTextStyles.body(color: AppColors.boldRed)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Solde à porter au compte : ${CurrencyFormatter.local(context, balanceDue)}',
                style: AppTextStyles.caption(color: AppColors.boldRed),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('cash-credit-search'),
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Rechercher un client par nom ou téléphone',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            ),
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...results.map((c) {
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(c.name, style: AppTextStyles.body()),
              subtitle: Text(
                c.isCreditBlocked ? '${c.phone} · BLOQUÉ' : c.phone,
                style: AppTextStyles.caption(
                  color: c.isCreditBlocked ? AppColors.boldRed : null,
                ),
              ),
              onTap: () {
                if (!c.isCreditBlocked) onCustomerSelected(c);
              },
            );
          }),
        ],
        TextButton.icon(
          key: const Key('cash-credit-new'),
          onPressed: onToggleNewForm,
          icon: Icon(
            showNewCustomer ? Icons.close : Icons.person_add_outlined,
            size: 16,
          ),
          label: Text(showNewCustomer ? 'Annuler' : 'Nouveau client'),
          style: TextButton.styleFrom(foregroundColor: AppColors.amber),
        ),
        if (showNewCustomer) ...[
          TextField(
            key: const Key('cash-credit-name'),
            controller: newNameCtrl,
            decoration: InputDecoration(
              labelText: 'Nom complet *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              ),
            ),
          ),
          const SizedBox(height: 8),
          PhoneField(
            key: const Key('cash-credit-phone'),
            controller: newPhoneCtrl,
            label: 'Téléphone *',
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('cash-credit-create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(40),
            ),
            onPressed: () {
              final name = newNameCtrl.text.trim();
              final phone = newPhoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              onCustomerCreated(
                Customer(
                  id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  phone: phone,
                  createdAt: DateTime.now(),
                ),
              );
            },
            child: const Text('Créer et choisir'),
          ),
        ],
      ],
    );
  }
}

// ─── Credit content ───────────────────────────────────────────────────────────

class _RCreditContent extends StatelessWidget {
  final double totalHtg;
  final bool isDark;
  final Customer? selectedCustomer;
  final String creditSearch;
  final double creditPartialPaid;
  final bool showNewCustomer;
  final TextEditingController newNameCtrl;
  final TextEditingController newPhoneCtrl;
  final TextEditingController partialCtrl;
  final CustomerState customerState;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onCustomerSelected;
  final VoidCallback onCustomerCleared;
  final ValueChanged<String> onPartialChanged;
  final VoidCallback onToggleNewForm;
  final ValueChanged<Customer> onCustomerCreated;

  const _RCreditContent({
    required this.totalHtg,
    required this.isDark,
    required this.selectedCustomer,
    required this.creditSearch,
    required this.creditPartialPaid,
    required this.showNewCustomer,
    required this.newNameCtrl,
    required this.newPhoneCtrl,
    required this.partialCtrl,
    required this.customerState,
    required this.onSearchChanged,
    required this.onCustomerSelected,
    required this.onCustomerCleared,
    required this.onPartialChanged,
    required this.onToggleNewForm,
    required this.onCustomerCreated,
  });

  @override
  Widget build(BuildContext context) {
    final results = creditSearch.isEmpty
        ? <Customer>[]
        : customerState.customers
              .where(
                (c) =>
                    c.isActive &&
                    (c.name.toLowerCase().contains(
                          creditSearch.toLowerCase(),
                        ) ||
                        c.phone.contains(creditSearch)),
              )
              .toList();

    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Text('Compte crédit', style: AppTextStyles.h3()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            if (selectedCustomer == null) ...[
              TextField(
                key: const Key('credit-client-search'),
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Rechercher un client par nom ou téléphone',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusInput,
                    ),
                  ),
                ),
              ),
              if (results.isNotEmpty) ...[
                const SizedBox(height: AppConstants.spacing8),
                ...results.map((c) {
                  final bal = customerState.balanceFor(c.id);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c.isCreditBlocked
                            ? AppColors.boldRed.withValues(alpha: 0.12)
                            : AppColors.lightBlue,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          c.name[0].toUpperCase(),
                          style: AppTextStyles.caption(
                            color: c.isCreditBlocked
                                ? AppColors.boldRed
                                : AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(c.name, style: AppTextStyles.body()),
                        ),
                        if (c.isCreditBlocked)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.boldRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'BLOQUÉ',
                              style: AppTextStyles.caption(
                                color: AppColors.boldRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${c.phone}${bal > 0 ? ' · Owes ${CurrencyFormatter.local(context, bal)}' : ''}',
                      style: AppTextStyles.caption(),
                    ),
                    onTap: () {
                      if (!c.isCreditBlocked) onCustomerSelected(c);
                    },
                  );
                }),
              ],
              const SizedBox(height: AppConstants.spacing8),
              TextButton.icon(
                onPressed: onToggleNewForm,
                icon: Icon(
                  showNewCustomer ? Icons.close : Icons.person_add_outlined,
                  size: 16,
                ),
                label: Text(showNewCustomer ? 'Annuler' : 'Nouveau client'),
                style: TextButton.styleFrom(foregroundColor: AppColors.amber),
              ),
              if (showNewCustomer) ...[
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: newNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nom complet *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusInput,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                PhoneField(
                  controller: newPhoneCtrl,
                  label: 'Téléphone *',
                ),
                const SizedBox(height: AppConstants.spacing8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                  onPressed: () {
                    final n = newNameCtrl.text.trim();
                    final p = newPhoneCtrl.text.trim();
                    if (n.isEmpty || p.isEmpty) return;
                    onCustomerCreated(
                      Customer(
                        id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
                        name: n,
                        phone: p,
                        createdAt: DateTime.now(),
                      ),
                    );
                  },
                  child: const Text('Créer et choisir'),
                ),
              ],
            ] else ...[
              if (selectedCustomer!.isCreditBlocked)
                Container(
                  key: const Key('credit-selected-client'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.boldRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.boldRed.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.block_outlined,
                        color: AppColors.boldRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedCustomer!.name,
                              style: AppTextStyles.body(
                                color: AppColors.boldRed,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (selectedCustomer!.phone.trim().isNotEmpty)
                              Text(
                                selectedCustomer!.phone,
                                style: AppTextStyles.caption(
                                  color: AppColors.boldRed,
                                ),
                              ),
                            Text(
                              '${selectedCustomer!.name} est bloqué.',
                              style: AppTextStyles.caption(
                                color: AppColors.boldRed,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('credit-client-clear'),
                        tooltip: 'Retirer le client',
                        onPressed: onCustomerCleared,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                )
              else ...[
                Container(
                  key: const Key('credit-selected-client'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primaryBlue.withValues(alpha: 0.2)
                        : AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            selectedCustomer!.name[0].toUpperCase(),
                            style: AppTextStyles.body(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedCustomer!.name,
                              style: AppTextStyles.body(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                            ),
                            if (selectedCustomer!.phone.trim().isNotEmpty)
                              Text(
                                selectedCustomer!.phone,
                                style: AppTextStyles.caption(),
                              ),
                            Builder(
                              builder: (ctx) {
                                final bal = customerState.balanceFor(
                                  selectedCustomer!.id,
                                );
                                if (bal <= 0) return const SizedBox.shrink();
                                return Text(
                                  'Owes ${CurrencyFormatter.local(ctx, bal)}',
                                  style: AppTextStyles.caption(
                                    color: AppColors.boldRed,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('credit-client-clear'),
                        tooltip: 'Retirer le client',
                        onPressed: onCustomerCleared,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (ctx) {
                    final bal = customerState.balanceFor(selectedCustomer!.id);
                    final limit = selectedCustomer!.creditLimitHtg;
                    final creditAmt = totalHtg - creditPartialPaid;
                    if (limit != null && (bal + creditAmt) > limit) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          top: AppConstants.spacing8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.boldRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.boldRed.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_outlined,
                                color: AppColors.boldRed,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'La limite de crédit sera dépassée.',
                                  style: AppTextStyles.caption(
                                    color: AppColors.boldRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: partialCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: InputFormatters.decimalAmount,
                  onChanged: onPartialChanged,
                  decoration: InputDecoration(
                    labelText: 'Montant payé maintenant (HTG) — facultatif',
                    prefixText: 'HTG ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusInput,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Payé maintenant', style: AppTextStyles.body()),
                    Text(
                      CurrencyFormatter.local(context, creditPartialPaid),
                      style: AppTextStyles.body(
                        color: AppColors.deepGreen,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sur compte crédit', style: AppTextStyles.body()),
                    Text(
                      CurrencyFormatter.local(
                        context,
                        totalHtg - creditPartialPaid,
                      ),
                      style: AppTextStyles.body(
                        color: AppColors.boldRed,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

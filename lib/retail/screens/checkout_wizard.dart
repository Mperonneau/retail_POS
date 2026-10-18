import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mock/mock_retail_data.dart';
import '../../core/mock/mock_retail_orders.dart';
import '../../core/models/customer.dart';
import '../../core/models/order_history.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import '../../core/providers/tax_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/payment_success_panel.dart';
import '../models/retail_cart_entry.dart';
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
  final _deliveryPhoneCtrl = TextEditingController();
  final _deliveryFeeCtrl = TextEditingController();

  RetailFulfillmentMode _fulfillment = RetailFulfillmentMode.inStore;
  double _deliveryFee = 0;
  String _searchQuery = '';
  /// Phone from directory selection (not the search field text).
  String _linkedClientPhone = '';
  bool _submitting = false;
  /// Shown on success screen (mock sale #).
  int _completedSaleNumber = 0;

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
      _deliveryPhoneCtrl.text = q.deliveryPhone ?? '';
    }
    // Steps: 0–2 checkout; 3 = payment confirmed (after pay only).
    const lastPayStep = 2;
    final initial = widget.initialStepIndex ?? (q != null ? lastPayStep : 0);
    _step = initial.clamp(0, lastPayStep);
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _clientEmailCtrl.dispose();
    _searchCtrl.dispose();
    _deliveryLocationCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _deliveryFeeCtrl.dispose();
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

  static bool _fulfillmentAllowed(
      RetailFulfillmentMode m, RetailSettings s) {
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
      if (_isDeliveryMode &&
          _deliveryPhoneCtrl.text.trim().isEmpty &&
          _linkedClientPhone.trim().isNotEmpty) {
        _deliveryPhoneCtrl.text = _linkedClientPhone;
      }
    });
  }

  void _onPickMockCustomer(MockCustomer c) {
    setState(() {
      _clientNameCtrl.text = c.name;
      _linkedClientPhone = c.phone;
      _searchCtrl.clear();
      _searchQuery = '';
      if (_isDeliveryMode && _deliveryPhoneCtrl.text.trim().isEmpty) {
        _deliveryPhoneCtrl.text = c.phone;
      }
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

  double _subtotal(List<RetailCartEntry> lines) => lines.fold(
        0.0,
        (s, e) => s + e.product.priceHtg * e.quantity,
      );

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
    final hasContact = _linkedClientPhone.trim().isNotEmpty ||
        _clientEmailCtrl.text.trim().isNotEmpty;
    return hasName && hasContact;
  }

  bool _validateDeliveryStep() {
    if (!_isDeliveryMode) return true;
    return _deliveryLocationCtrl.text.trim().isNotEmpty &&
        _deliveryPhoneCtrl.text.trim().isNotEmpty;
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
        .map((e) => MockQuoteLine(
              product: e.product,
              quantity: e.quantity,
              unitPriceHtg: e.product.priceHtg,
              unitPriceUsd: e.product.priceUsd,
            ))
        .toList();
    final existing = widget.existingQuote;
    if (existing != null && widget.isQuote) {
      ref.read(quotesProvider.notifier).updateQuote(
            existing.copyWith(
              lines: lines,
              clientName: _clientNameCtrl.text.trim().isEmpty
                  ? null
                  : _clientNameCtrl.text.trim(),
              clientPhone: _linkedClientPhone.trim().isEmpty
                  ? null
                  : _linkedClientPhone.trim(),
              clientEmail: _clientEmailCtrl.text.trim().isEmpty
                  ? null
                  : _clientEmailCtrl.text.trim(),
              fulfillmentMode: _fulfillmentSectionVisible
                  ? _fulfillment
                  : RetailFulfillmentMode.inStore,
              deliveryLocation:
                  _isDeliveryMode ? _deliveryLocationCtrl.text.trim() : null,
              deliveryPhone:
                  _isDeliveryMode ? _deliveryPhoneCtrl.text.trim() : null,
              discountPercent: widget.discountPercent,
              paymentLinkSent: false,
            ),
          );
    } else {
      ref.read(quotesProvider.notifier).add(
            MockRetailQuote(
              id: 'qte_${DateTime.now().millisecondsSinceEpoch}',
              quoteNumber: QuotesNotifier.newQuoteNumber(),
              checkoutId: _checkoutId,
              lines: lines,
              clientName: _clientNameCtrl.text.trim().isEmpty
                  ? null
                  : _clientNameCtrl.text.trim(),
              clientPhone: _linkedClientPhone.trim().isEmpty
                  ? null
                  : _linkedClientPhone.trim(),
              clientEmail: _clientEmailCtrl.text.trim().isEmpty
                  ? null
                  : _clientEmailCtrl.text.trim(),
              fulfillmentMode: _fulfillmentSectionVisible
                  ? _fulfillment
                  : RetailFulfillmentMode.inStore,
              deliveryLocation:
                  _isDeliveryMode ? _deliveryLocationCtrl.text.trim() : null,
              deliveryPhone:
                  _isDeliveryMode ? _deliveryPhoneCtrl.text.trim() : null,
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
    for (final e in lines) {
      final matches = products.where((p) => p.id == e.product.id).toList();
      if (matches.isEmpty) {
        failures.add('${e.product.name} — plus au catalogue');
        continue;
      }
      final live = matches.first;
      if (e.quantity > live.stockQuantity) {
        failures.add(
          '${e.product.name} — demandé ${e.quantity}, disponible ${live.stockQuantity}',
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
            child: Text('OK', style: AppTextStyles.button(color: AppColors.primaryBlue)),
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
                            color: AppColors.primaryBlue),
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
          deliveryLocationCtrl: _deliveryLocationCtrl,
          deliveryPhoneCtrl: _deliveryPhoneCtrl,
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
          linkedClientPhone: _linkedClientPhone,
          fulfillment: _fulfillmentSectionVisible
              ? _fulfillment
              : RetailFulfillmentMode.inStore,
          showFulfillmentChip: _fulfillmentSectionVisible,
          deliveryLocation: _deliveryLocationCtrl.text.trim(),
          deliveryPhone: _deliveryPhoneCtrl.text.trim(),
          deliveryFee: deliveryFee,
          showDeliveryFeeRow: _isDeliveryMode,
          isDark: isDark,
          isQuote: widget.isQuote,
          isUpdatingQuote:
              widget.existingQuote != null && widget.isQuote,
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
          onConfirm: (method) async {
            final map = {
              for (final e in lines) e.product.id: e.quantity,
            };
            final now = DateTime.now();
            final saleNo = 100 + (now.millisecondsSinceEpoch % 8999);
            final clientName = _clientNameCtrl.text.trim();
            ref.read(retailOrdersProvider.notifier).add(
                  RetailOrder(
                    id: 'pos-$_checkoutId',
                    orderNumber: 'ORD-${now.year}-$saleNo',
                    fromQuoteId: widget.existingQuote?.id,
                    clientName: clientName.isEmpty ? null : clientName,
                    clientPhone: _linkedClientPhone.trim().isEmpty
                        ? null
                        : _linkedClientPhone.trim(),
                    fulfillmentMode: _fulfillmentSectionVisible
                        ? _fulfillment
                        : RetailFulfillmentMode.inStore,
                    status: RetailOrderStatus.paid,
                    paymentSource: RetailPaymentSource.pos,
                    paymentMethod: method,
                    lines: [
                      for (final e in lines)
                        RetailOrderLine(
                          productName: e.product.name,
                          productId: e.product.id,
                          quantity: e.quantity,
                          unitPriceHtg: e.product.priceHtg,
                          unitPriceUsd: e.product.priceUsd,
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
                        ? _deliveryPhoneCtrl.text.trim()
                        : null,
                    createdAt: now,
                    paidAt: now,
                  ),
                );
            ref.read(mockProductsProvider.notifier).applySale(map);
            ref.read(retailInventoryLedgerProvider.notifier).recordSalesFromCheckout(
                  map,
                  DateTime.now(),
                );
            if (widget.existingQuote != null) {
              ref
                  .read(quotesProvider.notifier)
                  .convertToOrder(widget.existingQuote!.id);
            }
            if (!context.mounted) return;
            setState(() {
              _submitting = false;
              _completedSaleNumber = saleNo;
              _step = _successStepIndex;
            });
          },
        ),
      );
    }
    if (_step == _successStepIndex) {
      final name = _clientNameCtrl.text.trim();
      return KeyedSubtree(
        key: key,
        child: PaymentSuccessPanel(
          amountHtg: total,
          showHeader: true,
          contextSubtitle: _successContextSubtitle(),
          statusLine: 'Vente n°$_completedSaleNumber payée',
          receiptDetailLine:
              name.isNotEmpty ? 'Reçu pour : $name' : null,
          printReceiptName: name.isNotEmpty ? name : null,
          onDone: _finishPaymentSuccess,
          onHeaderBack: _finishPaymentSuccess,
          onHeaderClose: _finishPaymentSuccess,
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
  final TextEditingController deliveryLocationCtrl;
  final TextEditingController deliveryPhoneCtrl;
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
    required this.deliveryLocationCtrl,
    required this.deliveryPhoneCtrl,
    required this.deliveryFeeCtrl,
    required this.onDeliveryFeeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mockList = ref.watch(mockCustomersProvider);
    final results = searchQuery.trim().isEmpty
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
                  MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing8,
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
                TextField(
                  controller: clientNameCtrl,
                  decoration: InputDecoration(
                    labelText: isQuote
                        ? 'Nom du client *'
                        : 'Nom du client (facultatif)',
                    prefixIcon: const Icon(Icons.person_outline, size: 18),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
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
                      prefixIcon:
                          const Icon(Icons.email_outlined, size: 18),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppConstants.spacing4),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 13,
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray),
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
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    labelText: 'Rechercher un client',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
                    isDense: true,
                  ),
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  ...results.map(
                    (c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name, style: AppTextStyles.body()),
                      subtitle: Text(c.phone, style: AppTextStyles.caption()),
                      onTap: () => onPickMockCustomer(c),
                    ),
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
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.nearBlack;
                        }
                        return isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray;
                      }),
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
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
                                top: AppConstants.spacing12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppInput(
                                  label: 'Lieu *',
                                  controller: deliveryLocationCtrl,
                                  prefixIcon: Icons.place_outlined,
                                ),
                                const SizedBox(
                                    height: AppConstants.spacing8),
                                AppInput(
                                  label: 'Téléphone *',
                                  controller: deliveryPhoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: InputFormatters.phone,
                                  prefixIcon: Icons.phone_outlined,
                                ),
                                const SizedBox(
                                    height: AppConstants.spacing8),
                                AppInput(
                                  label: 'Frais de livraison (HTG)',
                                  controller: deliveryFeeCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
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
    final hasContext = clientName.isNotEmpty ||
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
                  color:
                      isDark ? AppColors.darkBorder : const Color(0xFFE8E8E8),
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
                          bottom: AppConstants.spacing8),
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
                              e.product.name,
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
                              CurrencyFormatter.amountOnly(
                                  e.product.priceHtg),
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
                                e.product.priceHtg * e.quantity,
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
                      padding:
                          const EdgeInsets.only(top: AppConstants.spacing4),
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
                                ? CurrencyFormatter.local(
                                    context, deliveryFee)
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
                  label: isUpdatingQuote ? 'Mettre à jour le devis' : 'Enregistrer comme devis',
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
          child: Text(
            'Qté',
            style: AppTextStyles.caption(color: headerColor),
          ),
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

  Widget _moneyRow(BuildContext context, String label, double amount, bool isDark) {
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
        Text(
          label,
          style: AppTextStyles.caption(color: color),
        ),
      ],
    );
  }
}

// ─── Payment (from POS) ───────────────────────────────────────────────────────

class _RetailPaymentPanel extends ConsumerStatefulWidget {
  final double total;
  final String checkoutId;
  final bool submitting;
  final Future<bool> Function() onValidateStock;
  final Future<void> Function(PaymentMethodType method) onConfirm;

  const _RetailPaymentPanel({
    required this.total,
    required this.checkoutId,
    required this.submitting,
    required this.onValidateStock,
    required this.onConfirm,
  });

  @override
  ConsumerState<_RetailPaymentPanel> createState() =>
      _RetailPaymentPanelState();
}

class _RetailPaymentPanelState extends ConsumerState<_RetailPaymentPanel> {
  _RPayMethod _method = _RPayMethod.moncash;

  // Cash
  double _cashReceived = 0;
  final _cashCtrl = TextEditingController();

  // Credit
  Customer? _selectedCustomer;
  String _creditSearch = '';
  double _creditPartialPaid = 0;
  bool _showNewCustomer = false;
  final _newNameCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _partialCtrl = TextEditingController();

  @override
  void dispose() {
    _cashCtrl.dispose();
    _newNameCtrl.dispose();
    _newPhoneCtrl.dispose();
    _partialCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (widget.submitting) return false;
    if (_method == _RPayMethod.credit) {
      return _selectedCustomer != null && !_selectedCustomer!.isCreditBlocked;
    }
    return true;
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    if (!await widget.onValidateStock()) return;
    if (_method == _RPayMethod.credit && _selectedCustomer != null) {
      final creditAmount = widget.total - _creditPartialPaid;
      if (creditAmount > 0) {
        final state = ref.read(customerProvider);
        final balance = state.balanceFor(_selectedCustomer!.id);
        final limit = _selectedCustomer!.creditLimitHtg;
        if (limit != null && (balance + creditAmount) > limit) return;
        ref.read(customerProvider.notifier).postCharge(
              customerId: _selectedCustomer!.id,
              amountHtg: widget.total,
              paidAmountHtg: _creditPartialPaid,
              cashierName: 'Caissier',
              description: 'Vente au détail',
            );
      }
    }
    await widget.onConfirm(switch (_method) {
      _RPayMethod.moncash => PaymentMethodType.moncash,
      _RPayMethod.card => PaymentMethodType.card,
      _RPayMethod.cash => PaymentMethodType.cash,
      _RPayMethod.credit => PaymentMethodType.credit,
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
                label: 'MonCash',
                icon: Icons.phone_android_outlined,
                selected: _method == _RPayMethod.moncash,
                onTap: () => setState(() => _method = _RPayMethod.moncash),
              ),
              _RetailMethodTab(
                label: 'Carte',
                icon: Icons.credit_card_outlined,
                selected: _method == _RPayMethod.card,
                onTap: () => setState(() => _method = _RPayMethod.card),
              ),
              _RetailMethodTab(
                label: 'Espèces',
                icon: Icons.payments_outlined,
                selected: _method == _RPayMethod.cash,
                onTap: () => setState(() => _method = _RPayMethod.cash),
              ),
              _RetailMethodTab(
                label: 'Crédit',
                icon: Icons.account_balance_wallet_outlined,
                selected: _method == _RPayMethod.credit,
                onTap: () => setState(() => _method = _RPayMethod.credit),
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
            label: widget.submitting ? 'Traitement…' : 'Confirmer le paiement',
            onPressed: _canConfirm ? _confirm : null,
            isLoading: widget.submitting,
            icon: Icons.check_circle_outline,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodContent(bool isDark, CustomerState customerState) {
    switch (_method) {
      case _RPayMethod.moncash:
        return _RMonCashContent(totalHtg: widget.total, isDark: isDark);
      case _RPayMethod.card:
        return _RCardContent(isDark: isDark);
      case _RPayMethod.cash:
        return _RCashContent(
          totalHtg: widget.total,
          cashReceived: _cashReceived,
          cashCtrl: _cashCtrl,
          isDark: isDark,
          onCashChanged: (v) =>
              setState(() => _cashReceived = double.tryParse(v) ?? 0),
          onQuickCash: (amt) {
            _cashCtrl.text = amt.toStringAsFixed(0);
            setState(() => _cashReceived = amt);
          },
        );
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
          onCustomerCleared: () => setState(() => _selectedCustomer = null),
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
    }
  }
}

// ─── Payment method enum ──────────────────────────────────────────────────────

enum _RPayMethod { moncash, card, cash, credit }

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
                  ? (accentColor != null ? AppColors.nearBlack : AppColors.white)
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
  const _RMonCashContent({required this.totalHtg, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_android_outlined,
              size: 44,
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
            ),
            const SizedBox(height: AppConstants.spacing12),
            Text('Paiement MonCash', style: AppTextStyles.h3()),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Saisissez le téléphone du client ou montrez le code QR',
              style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              decoration: InputDecoration(
                labelText: 'Téléphone du client',
                hintText: '+509 3XXX-XXXX',
                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput)),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: InputFormatters.phone,
            ),
            const SizedBox(height: AppConstants.spacing12),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.darkBackground : AppColors.lightBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2_rounded,
                      size: 52,
                      color:
                          isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                  Text('Code QR', style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(CurrencyFormatter.local(context, totalHtg),
                style: AppTextStyles.price()),
          ],
        ),
      ),
    );
  }
}

// ─── Card content ─────────────────────────────────────────────────────────────

class _RCardContent extends StatelessWidget {
  final bool isDark;
  const _RCardContent({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_outlined,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text('Paiement par carte', style: AppTextStyles.h3()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              decoration: InputDecoration(
                labelText: 'Numéro de carte',
                hintText: '1234 5678 9012 3456',
                prefixIcon: const Icon(Icons.credit_card, size: 20),
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput)),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: InputFormatters.cardNumber,
            ),
            const SizedBox(height: AppConstants.spacing8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Expiry',
                      hintText: 'MM/YY',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusInput)),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: InputFormatters.cardExpiry,
                  ),
                ),
                const SizedBox(width: AppConstants.spacing8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'CVV',
                      hintText: '123',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusInput)),
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: InputFormatters.cardCvv,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing4),
            Text('Propulsé par Stripe',
                style: AppTextStyles.caption(
                    color:
                        isDark ? AppColors.coolGray : AppColors.darkGray)),
          ],
        ),
      ),
    );
  }
}

// ─── Cash content ─────────────────────────────────────────────────────────────

class _RCashContent extends StatelessWidget {
  final double totalHtg;
  final double cashReceived;
  final TextEditingController cashCtrl;
  final bool isDark;
  final ValueChanged<String> onCashChanged;
  final ValueChanged<double> onQuickCash;

  const _RCashContent({
    required this.totalHtg,
    required this.cashReceived,
    required this.cashCtrl,
    required this.isDark,
    required this.onCashChanged,
    required this.onQuickCash,
  });

  @override
  Widget build(BuildContext context) {
    final change = cashReceived - totalHtg;
    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text('Paiement en espèces', style: AppTextStyles.h3()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Montant dû', style: AppTextStyles.body()),
                Text(CurrencyFormatter.local(context, totalHtg),
                    style: AppTextStyles.price()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: cashCtrl,
              onChanged: onCashChanged,
              decoration: InputDecoration(
                labelText: 'Espèces reçues (HTG)',
                prefixText: 'HTG ',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput)),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: InputFormatters.decimalAmount,
            ),
            const SizedBox(height: AppConstants.spacing8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [500, 1000, 2000, 5000, 10000]
                  .map((amt) => ActionChip(
                        label: Text(
                            CurrencyFormatter.compact(amt.toDouble())),
                        onPressed: () => onQuickCash(amt.toDouble()),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            if (change >= 0) ...[
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
          ],
        ),
      ),
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
            .where((c) =>
                c.isActive &&
                (c.name
                        .toLowerCase()
                        .contains(creditSearch.toLowerCase()) ||
                    c.phone.contains(creditSearch)))
            .toList();

    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text('Compte crédit', style: AppTextStyles.h3()),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            if (selectedCustomer == null) ...[
              TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Rechercher un client par nom ou téléphone',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput)),
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
                    title: Row(children: [
                      Expanded(
                          child: Text(c.name, style: AppTextStyles.body())),
                      if (c.isCreditBlocked)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.boldRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('BLOQUÉ',
                              style: AppTextStyles.caption(
                                  color: AppColors.boldRed)),
                        ),
                    ]),
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
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.amber),
              ),
              if (showNewCustomer) ...[
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: newNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nom complet *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusInput)),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: newPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: InputFormatters.phone,
                  decoration: InputDecoration(
                    labelText: 'Téléphone *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusInput)),
                  ),
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
                    onCustomerCreated(Customer(
                      id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
                      name: n,
                      phone: p,
                      createdAt: DateTime.now(),
                    ));
                  },
                  child: const Text('Créer et choisir'),
                ),
              ],
            ] else ...[
              if (selectedCustomer!.isCreditBlocked)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.boldRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.boldRed.withValues(alpha: 0.35)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.block_outlined,
                        color: AppColors.boldRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${selectedCustomer!.name} est BLOQUÉ',
                        style: AppTextStyles.body(color: AppColors.boldRed)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primaryBlue.withValues(alpha: 0.2)
                        : AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle),
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
                            Text(selectedCustomer!.name,
                                style: AppTextStyles.body(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack)),
                            Builder(builder: (ctx) {
                              final bal = customerState
                                  .balanceFor(selectedCustomer!.id);
                              if (bal <= 0) return const SizedBox.shrink();
                              return Text(
                                'Owes ${CurrencyFormatter.local(ctx, bal)}',
                                style: AppTextStyles.caption(
                                    color: AppColors.boldRed),
                              );
                            }),
                          ]),
                    ),
                    TextButton(
                      onPressed: onCustomerCleared,
                      child: const Text('Monnaie'),
                    ),
                  ]),
                ),
                Builder(builder: (ctx) {
                  final bal =
                      customerState.balanceFor(selectedCustomer!.id);
                  final limit = selectedCustomer!.creditLimitHtg;
                  final creditAmt = totalHtg - creditPartialPaid;
                  if (limit != null && (bal + creditAmt) > limit) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(top: AppConstants.spacing8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.boldRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppColors.boldRed.withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_outlined,
                              color: AppColors.boldRed, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('La limite de crédit sera dépassée.',
                                style: AppTextStyles.caption(
                                    color: AppColors.boldRed)),
                          ),
                        ]),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                const SizedBox(height: AppConstants.spacing8),
                TextField(
                  controller: partialCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  onChanged: onPartialChanged,
                  decoration: InputDecoration(
                    labelText: 'Montant payé maintenant (HTG) — facultatif',
                    prefixText: 'HTG ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusInput)),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payé maintenant', style: AppTextStyles.body()),
                      Text(CurrencyFormatter.local(context, creditPartialPaid),
                          style: AppTextStyles.body(color: AppColors.deepGreen)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ]),
                const SizedBox(height: 4),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sur compte crédit', style: AppTextStyles.body()),
                      Text(
                          CurrencyFormatter.local(
                              context, totalHtg - creditPartialPaid),
                          style: AppTextStyles.body(color: AppColors.boldRed)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
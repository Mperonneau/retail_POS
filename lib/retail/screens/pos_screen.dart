import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/providers/tax_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/barcode_scan_screen.dart';
import '../../core/widgets/discount_approval_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../models/product_option.dart';
import '../models/retail_cart_entry.dart';
import '../widgets/pos_product_detail.dart';
import '../widgets/product_option_picker.dart';
import 'checkout_wizard.dart';
import '../../core/widgets/app_close_button.dart';

/// Up to 5 columns on wide viewports; fewer on narrow screens so tiles stay usable.
int _posProductGridCrossAxisCount(double viewportWidth) {
  const gridHorizontalPadding = AppConstants.spacing12 * 2;
  const crossAxisSpacing = AppConstants.spacing8;
  const minTileWidth = 110.0;
  const maxColumns = 5;
  final inner = viewportWidth - gridHorizontalPadding;
  if (inner <= 0) return 2;
  final denom = minTileWidth + crossAxisSpacing;
  var n = ((inner + crossAxisSpacing) / denom).floor();
  if (n < 2) n = 2;
  if (n > maxColumns) n = maxColumns;
  return n;
}

/// Pass as GoRouter `extra` for [AppRoutes.retailPos].
class RetailPosRouteArgs {
  final bool quoteMode;
  final MockRetailQuote? quoteToEdit;

  const RetailPosRouteArgs({
    this.quoteMode = false,
    this.quoteToEdit,
  });

  static RetailPosRouteArgs parse(Object? extra) {
    if (extra is RetailPosRouteArgs) return extra;
    if (extra == true) return const RetailPosRouteArgs(quoteMode: true);
    return const RetailPosRouteArgs();
  }
}

class PosScreen extends ConsumerStatefulWidget {
  /// When true (e.g. navigated from Quotes), checkout can save as quote.
  final bool isQuoteMode;

  /// When set, POS cart and discount are prefilled and saving updates this quote.
  final MockRetailQuote? quoteToEdit;

  const PosScreen({
    super.key,
    this.isQuoteMode = false,
    this.quoteToEdit,
  });

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final List<RetailCartEntry> _cart = [];
  final Map<int, String> _qtyWarnings = {};
  final Map<int, Timer> _warningTimers = {};
  late final TextEditingController _productSearchController;
  String _search = '';
  String _category = 'Tous';
  double _discountPercent = 0;

  /// Embedded checkout (desktop: right column; mobile: slide-over panel).
  bool _checkoutActive = false;
  List<RetailCartEntry>? _checkoutCart;
  int _checkoutGeneration = 0;

  @override
  void initState() {
    super.initState();
    _productSearchController = TextEditingController();
    _productSearchController.addListener(_onProductSearchChanged);
    final q = widget.quoteToEdit;
    if (q != null) {
      _cart.clear();
      _cart.addAll(
        q.lines.map(
          (l) => RetailCartEntry(product: l.product, quantity: l.quantity),
        ),
      );
      _discountPercent = q.discountPercent;
    }
  }

  void _onProductSearchChanged() {
    final next = _productSearchController.text;
    if (next == _search) return;
    setState(() => _search = next);
  }

  /// Mobile-only: right slide-over for cart + checkout.
  bool _mobileCartPanelOpen = false;

  /// Product open from a card tap. The plus button does not set this.
  int? _detailProductId;

  final _categories = [
    'Tous',
    'Alimentation',
    'Boissons',
    'Ménage',
    'Électronique',
    'Hygiène',
    'Papeterie'
  ];

  int _cartQtyFor(int productId) => _cart
      .where((e) => e.product.id == productId)
      .fold(0, (sum, e) => sum + e.quantity);

  int _qtyForLine(MockProduct product, List<ProductOptionChoice> options) {
    final key = RetailCartEntry.lineKeyFor(product.id, options);
    final idx = _cart.indexWhere((e) => e.lineKey == key);
    return idx >= 0 ? _cart[idx].quantity : 0;
  }

  int? _roomFor(MockProduct product, List<ProductOptionChoice> options) {
    if (!product.trackStock) return null;
    final key = RetailCartEntry.lineKeyFor(product.id, options);
    final others = _cart
        .where((e) => e.product.id == product.id && e.lineKey != key)
        .fold(0, (sum, e) => sum + e.quantity);
    final room = product.stockQuantity - others;
    return room < 0 ? 0 : room;
  }

  void _setCartQty(
    MockProduct product,
    int requestedQty, {
    List<ProductOptionChoice> options = const [],
  }) {
    final key = RetailCartEntry.lineKeyFor(product.id, options);
    final idx = _cart.indexWhere((e) => e.lineKey == key);
    final room = _roomFor(product, options);
    final qty = room == null ? requestedQty : requestedQty.clamp(0, room).toInt();

    if (qty <= 0) {
      if (idx >= 0) _cart.removeAt(idx);
      return;
    }

    if (idx >= 0) {
      _cart[idx].quantity = qty;
      return;
    }

    _cart.add(RetailCartEntry(
      product: product,
      quantity: qty,
      options: options,
    ));
  }

  void _openProductDetail(MockProduct product) {
    setState(() {
      _detailProductId = product.id;
      _mobileCartPanelOpen = false;
    });
  }

  void _closeProductDetail() {
    if (_detailProductId == null) return;
    setState(() => _detailProductId = null);
  }

  Future<void> _addToCart(MockProduct p) async {
    if (p.options.isNotEmpty) {
      final picked = await showProductOptionPicker(context, p);
      if (picked == null || !mounted) return;
      final room = _roomFor(p, picked);
      if (room != null && _qtyForLine(p, picked) + 1 > room) {
        _showQtyWarning(p);
        return;
      }
      setState(() => _setCartQty(p, _qtyForLine(p, picked) + 1, options: picked));
      return;
    }
    final room = _roomFor(p, const []);
    if (room != null && _cartQtyFor(p.id) + 1 > room) {
      _showQtyWarning(p);
      return;
    }
    setState(() => _setCartQty(p, _cartQtyFor(p.id) + 1));
  }

  void _setLineQty(int index, int qty) {
    if (index < 0 || index >= _cart.length) return;
    setState(() {
      final entry = _cart[index];
      _setCartQty(entry.product, qty, options: entry.options);
    });
  }

  void _updateQty(MockProduct p, int delta) {
    if (delta > 0) {
      _addToCart(p);
      return;
    }
    setState(() {
      if (p.options.isNotEmpty) {
        final idx = _cart.lastIndexWhere((e) => e.product.id == p.id);
        if (idx < 0) return;
        final entry = _cart[idx];
        _setCartQty(entry.product, entry.quantity - 1, options: entry.options);
        return;
      }
      _setCartQty(p, _cartQtyFor(p.id) + delta);
    });
  }

  bool get _discountAllowed => ref.watch(discountAllowedProvider);

  double get _subtotal =>
      _cart.fold(0, (s, e) => s + (e.unitPriceHtg * e.quantity));
  double get _discountAmount => _subtotal * (_discountPercent / 100);
  double get _total => _subtotal - _discountAmount;

  Future<void> _onDiscountChanged(double newPercent, bool isDark) async {
    if (newPercent == 0) {
      setState(() => _discountPercent = 0);
      return;
    }
    final approved = await showDiscountApprovalDialog(
      context,
      ref,
      percent: newPercent,
      isDark: isDark,
    );
    if (approved == true && mounted) {
      setState(() => _discountPercent = newPercent);
    }
  }

  void _closeEmbeddedCheckout() {
    setState(() {
      _checkoutActive = false;
      _checkoutCart = null;
    });
  }

  void _closeMobileCartPanel() {
    setState(() {
      _mobileCartPanelOpen = false;
      _checkoutActive = false;
      _checkoutCart = null;
    });
  }

  void _startEmbeddedCheckout() {
    final cartCopy = _cart
        .map((e) => RetailCartEntry(product: e.product, quantity: e.quantity))
        .toList();
    setState(() {
      _checkoutGeneration++;
      _checkoutCart = cartCopy;
      _checkoutActive = true;
      if (MediaQuery.sizeOf(context).width <= 700) {
        _mobileCartPanelOpen = true;
      }
    });
  }

  Widget _checkoutWizard() {
    final cart = _checkoutCart!;
    return RetailCheckoutWizard(
      key: ValueKey(_checkoutGeneration),
      embedded: true,
      onDismiss: _closeEmbeddedCheckout,
      cart: cart,
      discountPercent: _discountPercent,
      isQuote: widget.isQuoteMode,
      existingQuote: widget.quoteToEdit,
      initialStepIndex: widget.quoteToEdit != null ? 0 : null,
      onSuccess: () {
        if (!mounted) return;
        setState(() {
          _cart.clear();
          _discountPercent = 0;
          _checkoutActive = false;
          _checkoutCart = null;
          _mobileCartPanelOpen = false;
        });
      },
      onQuoteSaved: widget.isQuoteMode
          ? () {
              if (!mounted) return;
              setState(() {
                _cart.clear();
                _discountPercent = 0;
                _checkoutActive = false;
                _checkoutCart = null;
                _mobileCartPanelOpen = false;
              });
              context.go(AppRoutes.retailQuotes);
            }
          : null,
    );
  }

  @override
  void dispose() {
    _productSearchController.removeListener(_onProductSearchChanged);
    _productSearchController.dispose();
    for (final t in _warningTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    String? code;
    if (BarcodeScanScreen.isSupported) {
      code = await BarcodeScanScreen.showModal(context);
    } else {
      final ctrl = TextEditingController();
      try {
        code = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Saisir le code-barres'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Code-barres ou SKU',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Rechercher'),
              ),
            ],
          ),
        );
      } finally {
        ctrl.dispose();
      }
    }
    if (!mounted || code == null || code.isEmpty) return;
    _applyBarcodeResult(code.trim());
  }

  void _applyBarcodeResult(String code) {
    final products = ref.read(mockProductsProvider);
    MockProduct? byBarcode;
    for (final p in products) {
      if (!p.active) continue;
      final b = p.barcode?.trim();
      if (b != null && b.toLowerCase() == code.toLowerCase()) {
        byBarcode = p;
        break;
      }
    }
    if (byBarcode != null) {
      _addToCart(byBarcode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${byBarcode.name} ajouté')),
      );
      return;
    }
    _productSearchController.text = code;
  }

  void _showQtyWarning(MockProduct product) {
    final id = product.id;
    _warningTimers[id]?.cancel();
    setState(() {
      _qtyWarnings[id] = 'Seulement ${product.stockQuantity} en stock';
    });
    _warningTimers[id] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _qtyWarnings.remove(id);
      });
    });
  }

  void _removeLineFromCart(MockProduct product) {
    final id = product.id;
    _warningTimers[id]?.cancel();
    _warningTimers.remove(id);
    setState(() {
      _qtyWarnings.remove(id);
      _setCartQty(product, 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 700;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelW = AppConstants.sidePanelWidth(width, 440.0);

    final rightPane = SizedBox(
      width: 440,
      child: _checkoutActive && _checkoutCart != null
          ? _checkoutWizard()
          : _buildCart(context),
    );

    final grid = _buildProductGrid(context);
    MockProduct? detailProduct;
    final detailId = _detailProductId;
    if (detailId != null) {
      for (final p in ref.watch(mockProductsProvider)) {
        if (p.id == detailId) {
          detailProduct = p;
          break;
        }
      }
      if (detailProduct == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _detailProductId == detailId) {
            setState(() => _detailProductId = null);
          }
        });
      }
    }

    Widget productPane = grid;
    if (detailProduct != null) {
      final product = detailProduct;
      productPane = LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final detailW = maxW <= AppConstants.mobileBreakpoint
              ? maxW
              : min(460.0, maxW);
          final full = detailW >= maxW;
          return Stack(
            fit: StackFit.expand,
            children: [
              grid,
              if (!full)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeProductDetail,
                    behavior: HitTestBehavior.opaque,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: detailW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: full
                        ? null
                        : Border(
                            left: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.darkGray.withValues(alpha: 0.25),
                            ),
                          ),
                  ),
                  child: _detailPanel(product),
                ),
              ),
            ],
          );
        },
      );
    }

    if (isWide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          children: [
            Expanded(flex: 3, child: productPane),
            const VerticalDivider(width: 1),
            rightPane,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: grid),
              if (_cart.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AppButton(
                      label:
                          'Panier (${_cart.length}) · ${CurrencyFormatter.local(context, _subtotal)}',
                      onPressed: () =>
                          setState(() => _mobileCartPanelOpen = true),
                      icon: Icons.shopping_cart_outlined,
                    ),
                  ),
                ),
            ],
          ),
          if (_mobileCartPanelOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMobileCartPanel,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.black54),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: panelW,
              child: Material(
                elevation: 16,
                color: isDark ? AppColors.darkSurface : AppColors.warmOffWhite,
                child: SafeArea(
                  left: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_checkoutActive) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                          child: Row(
                            children: [
                              AppCloseButton(onPressed: _closeMobileCartPanel),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Panier',
                                  style: AppTextStyles.h2(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                              if (_cart.isNotEmpty)
                                TextButton(
                                  onPressed: () => setState(() => _cart.clear()),
                                  child: Text(
                                    'Effacer',
                                    style: AppTextStyles.caption(
                                        color: AppColors.boldRed),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      Expanded(
                        child: _checkoutActive && _checkoutCart != null
                            ? _checkoutWizard()
                            : _buildCart(context, hideHeader: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (detailProduct != null)
            Positioned.fill(child: _detailPanel(detailProduct)),
        ],
      ),
    );
  }

  Widget _detailPanel(MockProduct product) {
    return PosProductDetail(
      product: product,
      cartLines: [
        for (final line in _cart)
          if (line.product.id == product.id) line,
      ],
      stockWarning: _qtyWarnings[product.id],
      onAdd: () => _addToCart(product),
      onDecrementLine: (line) {
        setState(() {
          _setCartQty(line.product, line.quantity - 1, options: line.options);
        });
      },
      onClose: _closeProductDetail,
    );
  }

  Widget _buildProductGrid(BuildContext context) {
    final products = ref.watch(mockProductsProvider).where((p) {
      final matchCat = _category == 'Tous' || p.category == _category;
      final matchSearch = _search.isEmpty ||
          p.name.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch && p.active;
    }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fillColor = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final isNarrow = w < AppConstants.mobileBreakpoint;
              final categoryWidth = isNarrow
                  ? (w * 0.34).clamp(108.0, 150.0)
                  : (w * 0.20).clamp(152.0, 220.0);
              final menuH = min(
                320.0,
                MediaQuery.sizeOf(context).height * 0.45,
              );

              // Shorter than default inputs so the filter bar leaves more room for the grid.
              const fieldMinHeight = AppConstants.buttonHeightCompact;
              const filterIconSize = 18.0;
              const pillRadius = 999.0;
              final pillBorder = OutlineInputBorder(
                borderRadius: BorderRadius.circular(pillRadius),
                borderSide: BorderSide(color: borderColor),
              );
              final pillFocusedBorder = OutlineInputBorder(
                borderRadius: BorderRadius.circular(pillRadius),
                borderSide: const BorderSide(
                  color: AppColors.primaryBlue,
                  width: 2,
                ),
              );
              // Fixed height so category and search match at any viewport width.
              final sharedFieldConstraints = BoxConstraints.tightFor(
                height: fieldMinHeight,
              );
              const sharedContentPadding = EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 12,
              );
              // [isCollapsed] removes extra padding around the trailing chevron in
              // [DropdownMenu] so the anchor stays the same height as the search field.
              // [contentPadding] must still be set explicitly when collapsed.
              final categoryInputTheme = InputDecorationTheme(
                filled: true,
                fillColor: fillColor,
                isDense: true,
                isCollapsed: true,
                contentPadding: sharedContentPadding,
                constraints: sharedFieldConstraints,
                prefixIconConstraints: BoxConstraints.tightFor(
                  height: fieldMinHeight,
                  width: 40,
                ),
                suffixIconConstraints: BoxConstraints.tightFor(
                  height: fieldMinHeight,
                  width: 36,
                ),
                border: pillBorder,
                enabledBorder: pillBorder,
                focusedBorder: pillFocusedBorder,
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: categoryWidth,
                    height: fieldMinHeight,
                    child: DropdownMenu<String>(
                      width: categoryWidth,
                      initialSelection: _categories.contains(_category)
                          ? _category
                          : 'Tous',
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      menuHeight: menuH,
                      hintText: 'Catégorie',
                      leadingIcon: Icon(
                        Icons.category_outlined,
                        size: filterIconSize,
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ),
                      trailingIcon: Icon(
                        Icons.arrow_drop_down_rounded,
                        size: filterIconSize + 2,
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ),
                      filterCallback:
                          (List<DropdownMenuEntry<String>> entries, String filter) {
                        final q = filter.trim().toLowerCase();
                        if (q.isEmpty) return entries;
                        return entries
                            .where(
                              (e) => e.label.toLowerCase().contains(q),
                            )
                            .toList();
                      },
                      inputDecorationTheme: categoryInputTheme,
                      textStyle: AppTextStyles.body(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack,
                      ),
                      onSelected: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                      dropdownMenuEntries: [
                        for (final c in _categories)
                          DropdownMenuEntry<String>(value: c, label: c),
                      ],
                    ),
                  ),
                  SizedBox(width: isNarrow ? 6 : 8),
                  Expanded(
                    child: SizedBox(
                      height: fieldMinHeight,
                      child: TextField(
                        controller: _productSearchController,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'Rechercher un produit ou scanner un code-barres...',
                          prefixIcon: Icon(Icons.search, size: filterIconSize),
                          prefixIconConstraints: BoxConstraints.tightFor(
                            height: fieldMinHeight,
                            width: 40,
                          ),
                          suffixIcon: _productSearchController.text
                                  .trim()
                                  .isNotEmpty
                              ? IconButton(
                                  tooltip: 'Effacer la recherche',
                                  onPressed: () {
                                    _productSearchController.clear();
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints.tightFor(
                                    width: 36,
                                    height: fieldMinHeight,
                                  ),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: filterIconSize,
                                    color: isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                )
                              : null,
                          suffixIconConstraints: BoxConstraints.tightFor(
                            height: fieldMinHeight,
                            width: 36,
                          ),
                          border: pillBorder,
                          enabledBorder: pillBorder,
                          focusedBorder: pillFocusedBorder,
                          filled: true,
                          fillColor: fillColor,
                          isDense: true,
                          contentPadding: sharedContentPadding.copyWith(
                            left: 4,
                            right: 16,
                          ),
                          constraints: sharedFieldConstraints,
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Scanner le code-barres',
                    child: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      iconSize: 22,
                      constraints: const BoxConstraints(
                        minWidth: AppConstants.minTouchTarget,
                        minHeight: AppConstants.minTouchTarget,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: _openBarcodeScanner,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_outlined,
                  title: 'Aucun produit',
                  message: 'Aucun produit ne correspond à votre recherche.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth <= AppConstants.mobileBreakpoint;
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: compact
                          ? const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppConstants.spacing8,
                              mainAxisSpacing: AppConstants.spacing8,
                              mainAxisExtent: 92,
                            )
                          : SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _posProductGridCrossAxisCount(
                                  constraints.maxWidth),
                              crossAxisSpacing: AppConstants.spacing8,
                              mainAxisSpacing: AppConstants.spacing8,
                              childAspectRatio: 1.32,
                            ),
                      itemCount: products.length,
                      itemBuilder: (_, i) {
                        final p = products[i];
                        final qty = _cartQtyFor(p.id);
                        return _ProductTile(
                          product: p,
                          cartQty: qty,
                          compact: compact,
                          onOpen: () => _openProductDetail(p),
                          onAdd: () => _addToCart(p),
                          onRemove: () => _updateQty(p, -1),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCart(BuildContext context, {bool hideHeader = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.warmOffWhite,
      child: Column(
        children: [
          if (!hideHeader) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Panier',
                          style: AppTextStyles.h2(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.primaryBlue,
                          ))),
                  if (_cart.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _cart.clear()),
                      child: Text('Effacer',
                          style:
                              AppTextStyles.caption(color: AppColors.boldRed)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Text(
                      'Le panier est vide',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 68,
                              child: Text(
                                'Qté',
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Article',
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 76,
                              child: Text(
                                'Unité',
                                textAlign: TextAlign.right,
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 76,
                              child: Text(
                                'Total',
                                textAlign: TextAlign.right,
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                          itemCount: _cart.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppConstants.spacing4),
                          itemBuilder: (_, i) {
                            final entry = _cart[i];
                            final warning = _qtyWarnings[entry.product.id];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _EditableQty(
                                      key: ValueKey(entry.lineKey),
                                      product: entry.product,
                                      quantity: entry.quantity,
                                      maxQty: _roomFor(entry.product, entry.options),
                                      onQtyCommitted: (q) => _setLineQty(i, q),
                                      onStockExceeded: () =>
                                          _showQtyWarning(entry.product),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: AppConstants.spacing4,
                                        ),
                                        child: Text(
                                          entry.lineLabel,
                                          style: AppTextStyles.caption(
                                            color: isDark
                                                ? AppColors.warmWhite
                                                : AppColors.nearBlack,
                                          ).copyWith(fontWeight: FontWeight.w500),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        CurrencyFormatter.amountOnly(
                                          entry.unitPriceHtg,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.caption(
                                          color: isDark
                                              ? AppColors.coolGray
                                              : AppColors.darkGray,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        CurrencyFormatter.amountOnly(
                                          entry.unitPriceHtg *
                                              entry.quantity,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.caption(
                                          color: isDark
                                              ? AppColors.warmWhite
                                              : AppColors.nearBlack,
                                        ).copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 24,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Tooltip(
                                          message: 'Retirer la ligne',
                                          child: GestureDetector(
                                            onTap: () => _removeLineFromCart(
                                              entry.product,
                                            ),
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: AppColors.boldRed
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Icon(
                                                Icons.remove,
                                                size: 12,
                                                color: AppColors.boldRed,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (warning != null) ...[
                                  const SizedBox(height: 2),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      warning,
                                      style: AppTextStyles.caption(
                                        color: AppColors.boldRed,
                                      ).copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Sous-total',
                  value: CurrencyFormatter.local(context, _subtotal),
                  isDark: isDark,
                ),
                if (_cart.isNotEmpty) ...[
                  if (_discountAllowed) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Remise',
                          style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_discountPercent > 0)
                              Text(
                                '-${CurrencyFormatter.local(context, _discountAmount)}  ',
                                style: AppTextStyles.caption(
                                    color: AppColors.deepGreen),
                              ),
                            DropdownButton<double>(
                              value: _discountPercent,
                              underline: const SizedBox(),
                              isDense: true,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                              items: [0, 5, 10, 15, 20].map((v) {
                                return DropdownMenuItem(
                                  value: v.toDouble(),
                                  child: Text('$v%'),
                                );
                              }).toList(),
                              onChanged: (v) {
                                final p = v ?? 0;
                                if (p == 0) {
                                  setState(() => _discountPercent = 0);
                                  return;
                                }
                                _onDiscountChanged(p, isDark);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        CurrencyFormatter.local(context, _total),
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                        ).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                AppButton(
                  label: widget.isQuoteMode ? 'Continuer' : 'Encaisser',
                  onPressed:
                      _cart.isEmpty ? null : () => _startEmbeddedCheckout(),
                  icon: Icons.arrow_forward_rounded,
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _ProductTile extends StatelessWidget {
  final MockProduct product;
  final int cartQty;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  /// Phone layout: two tiles per row, price and controls on one line.
  final bool compact;

  const _ProductTile({
    required this.product,
    required this.cartQty,
    required this.onOpen,
    required this.onAdd,
    required this.onRemove,
    this.compact = false,
  });

  Widget _stepButton({
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: foreground),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, bool isDark) {
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: product.isLowStock ? AppColors.amber : AppColors.deepGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.name,
                    style: AppTextStyles.caption(color: ink)
                        .copyWith(fontWeight: FontWeight.w600, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CurrencyFormatter.local(context, product.sellingPriceHtg),
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                      ).copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      product.trackStock
                          ? 'Stock : ${product.stockQuantity}'
                          : 'Stock non suivi',
                      style: AppTextStyles.caption(
                        color: product.isLowStock ? AppColors.amber : AppColors.darkGray,
                      ).copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (cartQty > 0) ...[
                _stepButton(
                  icon: Icons.remove,
                  background: AppColors.boldRed.withValues(alpha: 0.1),
                  foreground: AppColors.boldRed,
                  onTap: onRemove,
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '$cartQty',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: ink)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              _stepButton(
                icon: Icons.add,
                background: AppColors.amber,
                foreground: AppColors.nearBlack,
                onTap: onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inCart = cartQty > 0;

    return GestureDetector(
      onTap: onOpen,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        decoration: BoxDecoration(
          color: inCart
              ? (isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.2)
                  : AppColors.lightBlue)
              : (isDark ? AppColors.darkSurface : AppColors.white),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(
            color: inCart
                ? AppColors.primaryBlue.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
        ),
        child: compact ? _buildCompact(context, isDark) : Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacing12,
            2,
            AppConstants.spacing12,
            2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: product.isLowStock
                          ? AppColors.amber
                          : AppColors.deepGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Spacer(),
                  if (cartQty > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$cartQty',
                        style: AppTextStyles.caption(color: AppColors.nearBlack)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          product.name,
                          style: AppTextStyles.caption(
                            color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                          ).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.local(context, product.sellingPriceHtg),
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      product.trackStock
                          ? 'Stock : ${product.stockQuantity}'
                          : 'Stock non suivi',
                      style: AppTextStyles.caption(
                        color: product.isLowStock
                            ? AppColors.amber
                            : AppColors.darkGray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (cartQty > 0) ...[
                    GestureDetector(
                      onTap: onRemove,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.boldRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.remove,
                          size: 14,
                          color: AppColors.boldRed,
                        ),
                      ),
                    ),
                    Text(
                      '$cartQty',
                      style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ] else
                    const SizedBox(width: 26),
                  GestureDetector(
                    onTap: onAdd,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: AppColors.nearBlack,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableQty extends StatefulWidget {
  final MockProduct product;
  final int quantity;
  final int? maxQty;
  final ValueChanged<int> onQtyCommitted;
  final VoidCallback onStockExceeded;

  const _EditableQty({
    super.key,
    required this.product,
    required this.quantity,
    required this.maxQty,
    required this.onQtyCommitted,
    required this.onStockExceeded,
  });

  @override
  State<_EditableQty> createState() => _EditableQtyState();
}

class _EditableQtyState extends State<_EditableQty> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.quantity}');
  }

  @override
  void didUpdateWidget(covariant _EditableQty oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && !_focus.hasFocus) {
      _ctrl.text = '${widget.quantity}';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _validateAndCommit(int v, {required bool showWarning}) {
    if (v <= 0) return false;
    if (widget.maxQty != null && v > widget.maxQty!) {
      if (showWarning) widget.onStockExceeded();
      _ctrl.text = '${widget.quantity}';
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
      return false;
    }
    widget.onQtyCommitted(v);
    return true;
  }

  void _commit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0) {
      _ctrl.text = '${widget.quantity}';
      return;
    }
    _validateAndCommit(v, showWarning: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC);
    return SizedBox(
      width: 68,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        textAlign: TextAlign.center,
        style: AppTextStyles.body(
          color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
        ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              width: 2,
            ),
          ),
        ),
        onTap: () {
          _ctrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _ctrl.text.length,
          );
        },
        onChanged: (v) {
          _debounce?.cancel();
          final parsed = int.tryParse(v.trim());
          if (parsed == null || parsed <= 0) return;
          _debounce = Timer(const Duration(milliseconds: 250), () {
            if (!mounted) return;
            _validateAndCommit(parsed, showWarning: true);
          });
        },
        onEditingComplete: _commit,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// Compact summary row for the cart totals section.
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.caption(
      color: isDark ? AppColors.coolGray : AppColors.darkGray,
    );
    final valueStyle = AppTextStyles.caption(
      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

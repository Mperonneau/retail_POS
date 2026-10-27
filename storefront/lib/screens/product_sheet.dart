import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/retail/models/sale_measure.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';

import '../api.dart';
import '../cart.dart';
import '../money.dart';
import '../widgets.dart';

Future<T?> showStoreSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.white,
    constraints: const BoxConstraints(maxWidth: kPhoneMaxWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

Future<void> showProductSheet(
  BuildContext context, {
  required Shop shop,
  required Product product,
  required Cart cart,
}) {
  return showStoreSheet(
    context,
    (_) => _ProductSheet(shop: shop, product: product, cart: cart),
  );
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({
    required this.shop,
    required this.product,
    required this.cart,
  });

  final Shop shop;
  final Product product;
  final Cart cart;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final Map<String, Set<String>> _picked = {};
  final _widthCtrl = TextEditingController();
  MeasureKind? _kind;
  int _qty = 1;
  String? _error;

  Product get _p => widget.product;

  @override
  void dispose() {
    _widthCtrl.dispose();
    super.dispose();
  }

  List<OptionChoice> get _choices => [
    for (final g in _p.options)
      for (final c in g.choices)
        if (_picked[g.id]?.contains(c.id) ?? false) c,
  ];

  MeasureChoice? get _choice {
    if (_p.saleMode == SaleMode.piece) return const MeasureChoice.plain();
    return switch (_kind) {
      MeasureKind.fullRoll => const MeasureChoice.fullRoll(),
      MeasureKind.casePack => const MeasureChoice.casePack(),
      MeasureKind.each => const MeasureChoice.each(),
      MeasureKind.width => _widthChoice,
      _ => null,
    };
  }

  MeasureChoice? get _widthChoice {
    final width = int.tryParse(_widthCtrl.text.trim());
    if (width == null) return null;
    return MeasureChoice.width(width);
  }

  double? get _unit {
    final choice = _choice;
    if (choice == null) return null;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.lengthCap,
        ) !=
        null) {
      return null;
    }
    final extra = _choices.fold<double>(0, (s, c) => s + c.deltaHtg);
    return choice.baseHtg(
          priceHtg: _p.priceHtg,
          rollPriceHtg: _p.rollPriceHtg,
          casePriceHtg: _p.casePriceHtg,
        ) +
        extra;
  }

  int get _room {
    final choice = _choice;
    if (choice == null) return 0;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.lengthCap,
        ) !=
        null) {
      return 0;
    }
    if (!_p.trackStock) {
      return _p.maxQuantity - widget.cart.quantityOf(_p.id);
    }
    final each = choice.unitsEach(
      rollWidth: _p.rollWidth,
      unitsPerCase: _p.unitsPerCase,
    );
    if (each < 1) return 0;
    final left = _p.stock - widget.cart.stockUsed(_p.id);
    if (left <= 0) return 0;
    return left ~/ each;
  }

  bool get _canOrder =>
      widget.shop.availability.acceptsOrders ||
      widget.shop.availability.acceptsQuotes;

  double? get _widthTotal {
    final choice = _widthChoice;
    if (choice == null) return null;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.lengthCap,
        ) !=
        null) {
      return null;
    }
    return _p.priceHtg * choice.width;
  }

  String get _widthSentence {
    final width = int.tryParse(_widthCtrl.text.trim());
    if (width == null || width < 1) {
      return 'Le total est le prix par pouce × la longueur.';
    }
    if (_p.lengthCap >= 1 && width > _p.lengthCap) {
      return 'Le maximum est ${_p.lengthCap} po.';
    }
    if (width < _p.minWidth) return 'Le minimum est ${_p.minWidth} po.';
    return '$width po × ${Money.htg(_p.priceHtg)} = ${Money.htg(_p.priceHtg * width)}';
  }

  void _toggle(OptionGroup g, OptionChoice c) {
    setState(() {
      _error = null;
      final set = _picked.putIfAbsent(g.id, () => {});
      if (g.multiple) {
        set.contains(c.id) ? set.remove(c.id) : set.add(c.id);
      } else {
        final wasOn = set.contains(c.id);
        set.clear();
        if (!wasOn || g.required) set.add(c.id);
      }
    });
  }

  void _add() {
    final missing = _p.options
        .where((g) => g.required && (_picked[g.id]?.isEmpty ?? true))
        .map((g) => g.name)
        .toList();
    if (missing.isNotEmpty) {
      setState(() => _error = 'Choisissez : ${missing.join(', ')}.');
      return;
    }
    final choice = _choice;
    final reason = choice?.rejectReason(
      mode: _p.saleMode,
      minWidth: _p.minWidth,
      maxWidth: _p.lengthCap,
    );
    if (choice == null || reason != null) {
      setState(() {
        _error =
            reason ??
            (_p.saleMode == SaleMode.roll
                ? 'Choisissez la longueur entière ou une longueur.'
                : 'Choisissez une caisse ou une unité.');
      });
      return;
    }
    if (!widget.cart.add(_p, _choices, _qty, measure: choice)) {
      setState(() => _error = 'Il ne reste pas assez de stock.');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.shop.usdRate;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: 0.5,
      maxChildSize: 1,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: _p.saleMode == SaleMode.piece ? 4 / 3 : 2,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        child: ProductPhoto(url: _p.photoUrl, name: _p.name),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: AppCloseButton(
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _p.category.toUpperCase(),
                        style:
                            AppTextStyles.caption(
                              color: AppColors.primaryBlue,
                            ).copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _p.name,
                        style: AppTextStyles.h1(
                          color: AppColors.nearBlack,
                        ).copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 10),
                      if (_p.saleMode == SaleMode.piece) ...[
                        DualPrice(
                          htg: _p.priceHtg,
                          rate: rate,
                          large: true,
                          regularHtg: _p.regularPriceHtg,
                        ),
                        if (_p.unit.isNotEmpty)
                          Text(
                            'Prix par ${_p.unit}',
                            style: AppTextStyles.caption(),
                          ),
                      ] else ...[
                        Text(
                          _p.saleMode == SaleMode.roll
                              ? 'Prenez la longueur entière, ou indiquez une longueur en pouces.'
                              : 'Prenez une caisse, ou une seule unité.',
                          style: AppTextStyles.body(
                            color: AppColors.darkGray,
                          ).copyWith(fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        if (_p.saleMode == SaleMode.roll) ...[
                          _MeasureCard(
                            selected: _kind == MeasureKind.fullRoll,
                            title: 'Longueur entière',
                            detail: '${_p.rollWidth} pouces',
                            htg: _p.rollPriceHtg,
                            regularHtg: _p.regularRollPriceHtg,
                            rate: rate,
                            onTap: () => setState(() {
                              _kind = MeasureKind.fullRoll;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 10),
                          _MeasureCard(
                            selected: _kind == MeasureKind.width,
                            title: 'Entrer une longueur',
                            detail: _p.lengthCap >= 1
                                ? '${Money.htg(_p.priceHtg)} par pouce · minimum ${_p.minWidth} po · maximum ${_p.lengthCap} po'
                                : '${Money.htg(_p.priceHtg)} par pouce · minimum ${_p.minWidth} po',
                            htg: _widthTotal,
                            rate: rate,
                            onTap: () => setState(() {
                              _kind = MeasureKind.width;
                              _error = null;
                            }),
                          ),
                          if (_kind == MeasureKind.width) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _widthCtrl,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                MaxInchesFormatter(_p.lengthCap),
                              ],
                              // iPhone zooms the page on a field under 16 px.
                              style: AppTextStyles.body(
                                color: AppColors.nearBlack,
                              ).copyWith(fontSize: 16),
                              decoration: const InputDecoration(
                                labelText: 'Longueur (pouces)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() => _error = null),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _widthSentence,
                              style: AppTextStyles.caption(),
                            ),
                          ],
                        ] else ...[
                          _MeasureCard(
                            selected: _kind == MeasureKind.casePack,
                            title: 'Une caisse',
                            detail: '${_p.unitsPerCase} unités',
                            htg: _p.casePriceHtg,
                            regularHtg: _p.regularCasePriceHtg,
                            rate: rate,
                            onTap: () => setState(() {
                              _kind = MeasureKind.casePack;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 10),
                          _MeasureCard(
                            selected: _kind == MeasureKind.each,
                            title: 'Une unité',
                            detail: 'Vendue seule',
                            htg: _p.priceHtg,
                            regularHtg: _p.regularPriceHtg,
                            rate: rate,
                            onTap: () => setState(() {
                              _kind = MeasureKind.each;
                              _error = null;
                            }),
                          ),
                        ],
                      ],
                      if (_p.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _p.description,
                          style: AppTextStyles.body(
                            color: AppColors.darkGray,
                          ).copyWith(fontSize: 14, height: 1.5),
                        ),
                      ],
                      for (final g in _p.options) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              g.name,
                              style: AppTextStyles.h2(
                                color: AppColors.nearBlack,
                              ).copyWith(fontSize: 15),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              g.required
                                  ? 'Obligatoire'
                                  : (g.multiple
                                        ? 'Plusieurs choix'
                                        : 'Facultatif'),
                              style: AppTextStyles.caption(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in g.choices)
                              ChoiceChip(
                                label: Text(
                                  c.deltaHtg > 0
                                      ? '${c.name}  +${Money.usdFromHtg(c.deltaHtg, rate).replaceFirst('US ', '')}'
                                      : c.name,
                                ),
                                selected:
                                    _picked[g.id]?.contains(c.id) ?? false,
                                showCheckmark: false,
                                selectedColor: AppColors.lightBlue,
                                side: BorderSide(
                                  color:
                                      (_picked[g.id]?.contains(c.id) ?? false)
                                      ? AppColors.primaryBlue
                                      : const Color(0xFFE0E0E0),
                                ),
                                labelStyle: AppTextStyles.body(
                                  color: AppColors.nearBlack,
                                ).copyWith(fontWeight: FontWeight.w600),
                                onSelected: (_) => _toggle(g, c),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_p.available && _canOrder)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEFEDE8))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: AppTextStyles.errorText().copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        QtyStepper(
                          value: _qty,
                          onMinus: _qty > 1
                              ? () => setState(() => _qty--)
                              : null,
                          onPlus: _qty < _room
                              ? () => setState(() => _qty++)
                              : null,
                        ),
                        const SizedBox(width: AppConstants.spacing16),
                        Expanded(
                          child: AppButton(
                            label: _unit == null
                                ? 'Choisissez'
                                : 'Ajouter · ${Money.usdFromHtg(_unit! * _qty, rate)}',
                            icon: Icons.shopping_bag_outlined,
                            onPressed: _room > 0 ? _add : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MeasureCard extends StatelessWidget {
  const _MeasureCard({
    required this.selected,
    required this.title,
    required this.detail,
    required this.rate,
    required this.onTap,
    this.htg,
    this.regularHtg = 0,
  });

  final bool selected;
  final String title;
  final String detail;
  final double rate;
  final VoidCallback onTap;
  final double? htg;
  final double regularHtg;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lightBlue : const Color(0xFFF7F5F0),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : const Color(0xFFE4E0D8),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primaryBlue : AppColors.darkGray,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body(
                        color: AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(detail, style: AppTextStyles.caption()),
                  ],
                ),
              ),
              if (htg != null)
                DualPrice(
                  htg: htg!,
                  rate: rate,
                  regularHtg: regularHtg,
                  alignEnd: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

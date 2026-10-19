import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
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
    builder: builder,
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
  const _ProductSheet({required this.shop, required this.product, required this.cart});

  final Shop shop;
  final Product product;
  final Cart cart;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final Map<String, Set<String>> _picked = {};
  int _qty = 1;
  String? _error;

  Product get _p => widget.product;

  List<OptionChoice> get _choices => [
        for (final g in _p.options)
          for (final c in g.choices)
            if (_picked[g.id]?.contains(c.id) ?? false) c,
      ];

  double get _unit => _p.priceHtg + _choices.fold<double>(0, (s, c) => s + c.deltaHtg);

  int get _room => _p.maxQuantity - widget.cart.quantityOf(_p.id);

  bool get _canOrder =>
      widget.shop.availability.acceptsOrders || widget.shop.availability.acceptsQuotes;

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
    if (!widget.cart.add(_p, _choices, _qty)) {
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
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
                      aspectRatio: 4 / 3,
                      child: ClipRRect(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(22)),
                        child: ProductPhoto(url: _p.photoUrl, name: _p.name),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_p.category.toUpperCase(),
                          style: AppTextStyles.caption(color: AppColors.primaryBlue)
                              .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(_p.name,
                          style: AppTextStyles.h1(color: AppColors.nearBlack)
                              .copyWith(fontSize: 22)),
                      const SizedBox(height: 10),
                      DualPrice(
                        htg: _p.priceHtg,
                        rate: rate,
                        large: true,
                        regularHtg: _p.regularPriceHtg,
                      ),
                      if (_p.unit.isNotEmpty)
                        Text('Prix par ${_p.unit}', style: AppTextStyles.caption()),
                      if (_p.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(_p.description,
                            style: AppTextStyles.body(color: AppColors.darkGray)
                                .copyWith(fontSize: 14, height: 1.5)),
                      ],
                      for (final g in _p.options) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(g.name,
                                style: AppTextStyles.h2(color: AppColors.nearBlack)
                                    .copyWith(fontSize: 15)),
                            const SizedBox(width: 8),
                            Text(
                              g.required
                                  ? 'Obligatoire'
                                  : (g.multiple ? 'Plusieurs choix' : 'Facultatif'),
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
                                label: Text(c.deltaHtg > 0
                                    ? '${c.name}  +${Money.usdFromHtg(c.deltaHtg, rate).replaceFirst('US ', '')}'
                                    : c.name),
                                selected: _picked[g.id]?.contains(c.id) ?? false,
                                showCheckmark: false,
                                selectedColor: AppColors.lightBlue,
                                side: BorderSide(
                                  color: (_picked[g.id]?.contains(c.id) ?? false)
                                      ? AppColors.primaryBlue
                                      : const Color(0xFFE0E0E0),
                                ),
                                labelStyle: AppTextStyles.body(color: AppColors.nearBlack)
                                    .copyWith(fontWeight: FontWeight.w600),
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
                      Text(_error!, style: AppTextStyles.errorText().copyWith(fontSize: 13)),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        QtyStepper(
                          value: _qty,
                          onMinus: _qty > 1 ? () => setState(() => _qty--) : null,
                          onPlus: _qty < _room ? () => setState(() => _qty++) : null,
                        ),
                        const SizedBox(width: AppConstants.spacing16),
                        Expanded(
                          child: AppButton(
                            label: 'Ajouter · ${Money.usdFromHtg(_unit * _qty, rate)}',
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

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/mock/mock_retail_data.dart';
import '../models/product_option.dart';

/// Asks the cashier to pick this product's options. Returns null if dismissed.
Future<List<ProductOptionChoice>?> showProductOptionPicker(
  BuildContext context,
  MockProduct product,
) {
  return showAppBottomSheet<List<ProductOptionChoice>>(
    context: context,
    child: _ProductOptionPicker(product: product),
  );
}

class _ProductOptionPicker extends StatefulWidget {
  const _ProductOptionPicker({required this.product});

  final MockProduct product;

  @override
  State<_ProductOptionPicker> createState() => _ProductOptionPickerState();
}

class _ProductOptionPickerState extends State<_ProductOptionPicker> {
  final Map<String, Set<String>> _selected = {};
  String? _error;

  bool get _complete {
    for (final group in widget.product.options) {
      if (!group.required) continue;
      final picked = _selected[group.id];
      if (picked == null || picked.isEmpty) return false;
    }
    return true;
  }

  double get _extra {
    var sum = 0.0;
    for (final group in widget.product.options) {
      final picked = _selected[group.id] ?? const <String>{};
      for (final choice in group.choices) {
        if (picked.contains(choice.id)) sum += choice.priceDeltaHtg;
      }
    }
    return sum;
  }

  void _toggle(ProductOptionGroup group, ProductOptionChoice choice) {
    setState(() {
      _error = null;
      final set = _selected.putIfAbsent(group.id, () => <String>{});
      if (group.multiple) {
        if (!set.add(choice.id)) set.remove(choice.id);
      } else {
        set
          ..clear()
          ..add(choice.id);
      }
    });
  }

  void _confirm() {
    if (!_complete) {
      setState(() => _error = 'Choisissez chaque option obligatoire.');
      return;
    }
    final chosen = <ProductOptionChoice>[];
    for (final group in widget.product.options) {
      final picked = _selected[group.id] ?? const <String>{};
      for (final choice in group.choices) {
        if (picked.contains(choice.id)) chosen.add(choice);
      }
    }
    Navigator.pop(context, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final total = widget.product.sellingPriceHtg + _extra;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            children: [
              Text(
                widget.product.name,
                style: AppTextStyles.h2(color: ink),
              ),
              const SizedBox(height: 4),
              Text(
                CurrencyFormatter.local(context, widget.product.sellingPriceHtg),
                style: AppTextStyles.body(
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppConstants.spacing16),
              for (final group in widget.product.options) ...[
                Text(
                  group.required ? '${group.name} · obligatoire' : group.name,
                  style: AppTextStyles.body(color: ink).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  group.multiple ? 'Plusieurs choix possibles' : 'Un seul choix',
                  style: AppTextStyles.caption(color: muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in group.choices)
                      FilterChip(
                        label: Text(_choiceLabel(context, choice)),
                        selected: _selected[group.id]?.contains(choice.id) ?? false,
                        onSelected: (_) => _toggle(group, choice),
                      ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing16),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: AppTextStyles.caption(color: AppColors.boldRed),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: AppButton(
            label: 'Ajouter · ${CurrencyFormatter.local(context, total)}',
            onPressed: _confirm,
            compact: true,
          ),
        ),
      ],
    );
  }

  String _choiceLabel(BuildContext context, ProductOptionChoice choice) {
    if (choice.priceDeltaHtg == 0) return choice.name;
    return '${choice.name} · +${CurrencyFormatter.local(context, choice.priceDeltaHtg)}';
  }
}

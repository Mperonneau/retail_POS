import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../models/product_option.dart';
import '../models/sale_measure.dart';

class SaleMeasureResult {
  const SaleMeasureResult({
    required this.measure,
    required this.options,
    required this.quantity,
  });

  final MeasureChoice measure;
  final List<ProductOptionChoice> options;
  final int quantity;
}

/// How many more of this choice fit in stock. Null means stock is not tracked.
typedef MeasureRoom =
    int? Function(MeasureChoice measure, List<ProductOptionChoice> options);

/// Asks for the roll or the case, then returns the line to add.
Future<SaleMeasureResult?> showSaleMeasurePicker(
  BuildContext context,
  MockProduct product, {
  required MeasureRoom roomFor,
}) {
  return showAppBottomSheet<SaleMeasureResult>(
    context: context,
    child: _SaleMeasurePicker(product: product, roomFor: roomFor),
  );
}

class _SaleMeasurePicker extends StatefulWidget {
  const _SaleMeasurePicker({required this.product, required this.roomFor});

  final MockProduct product;
  final MeasureRoom roomFor;

  @override
  State<_SaleMeasurePicker> createState() => _SaleMeasurePickerState();
}

class _SaleMeasurePickerState extends State<_SaleMeasurePicker> {
  final _widthCtrl = TextEditingController();
  final Map<String, Set<String>> _selected = {};
  MeasureKind? _kind;
  int _qty = 1;
  String? _error;

  MockProduct get _p => widget.product;

  @override
  void dispose() {
    _widthCtrl.dispose();
    super.dispose();
  }

  MeasureChoice? get _choice {
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

  List<ProductOptionChoice> get _options {
    final chosen = <ProductOptionChoice>[];
    for (final group in _p.options) {
      final picked = _selected[group.id] ?? const <String>{};
      for (final choice in group.choices) {
        if (picked.contains(choice.id)) chosen.add(choice);
      }
    }
    return chosen;
  }

  bool get _optionsComplete {
    for (final group in _p.options) {
      if (!group.required) continue;
      final picked = _selected[group.id];
      if (picked == null || picked.isEmpty) return false;
    }
    return true;
  }

  int? get _room {
    final choice = _choice;
    if (choice == null) return 0;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.rollWidth,
        ) !=
        null) {
      return 0;
    }
    return widget.roomFor(choice, _options);
  }

  double get _extra =>
      _options.fold<double>(0, (sum, choice) => sum + choice.priceDeltaHtg);

  double? get _unit {
    final choice = _choice;
    if (choice == null) return null;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.rollWidth,
        ) !=
        null) {
      return null;
    }
    return _p.priceFor(choice) + _extra;
  }

  void _select(MeasureKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      final room = _room;
      if (room != null && _qty > room) _qty = room < 1 ? 1 : room;
    });
  }

  void _confirm() {
    final choice = _choice;
    final reason = choice?.rejectReason(
      mode: _p.saleMode,
      minWidth: _p.minWidth,
      maxWidth: _p.rollWidth,
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
    if (!_optionsComplete) {
      setState(() => _error = 'Choisissez chaque option obligatoire.');
      return;
    }
    final room = _room;
    if (room != null && (room < 1 || _qty > room)) {
      setState(() => _error = 'Il ne reste pas assez de stock.');
      return;
    }
    Navigator.pop(
      context,
      SaleMeasureResult(measure: choice, options: _options, quantity: _qty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final unit = _unit;
    final room = _room;
    final intro = _p.saleMode == SaleMode.roll
        ? 'Prenez la longueur entière, ou indiquez une longueur en pouces.'
        : 'Prenez une caisse, ou une seule unité.';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            children: [
              Text(_p.name, style: AppTextStyles.h2(color: ink)),
              const SizedBox(height: 6),
              Text(intro, style: AppTextStyles.body(color: muted)),
              const SizedBox(height: AppConstants.spacing16),
              if (_p.saleMode == SaleMode.roll) ...[
                _ChoiceCard(
                  selected: _kind == MeasureKind.fullRoll,
                  title: 'Longueur entière',
                  detail: '${_p.rollWidth} pouces',
                  price: CurrencyFormatter.local(
                    context,
                    _p.sellingRollPriceHtg,
                  ),
                  onTap: () => _select(MeasureKind.fullRoll),
                ),
                const SizedBox(height: 10),
                _ChoiceCard(
                  selected: _kind == MeasureKind.width,
                  title: 'Entrer une longueur',
                  detail: _lengthDetail(context),
                  price: _widthPrice(context),
                  onTap: () => _select(MeasureKind.width),
                ),
                if (_kind == MeasureKind.width) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _widthCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      MaxInchesFormatter(_p.rollWidth),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Longueur (pouces)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _widthSentence(context),
                    style: AppTextStyles.caption(color: muted),
                  ),
                ],
              ] else ...[
                _ChoiceCard(
                  selected: _kind == MeasureKind.casePack,
                  title: 'Une caisse',
                  detail: '${_p.unitsPerCase} unités',
                  price: CurrencyFormatter.local(
                    context,
                    _p.sellingCasePriceHtg,
                  ),
                  onTap: () => _select(MeasureKind.casePack),
                ),
                const SizedBox(height: 10),
                _ChoiceCard(
                  selected: _kind == MeasureKind.each,
                  title: 'Une unité',
                  detail: 'Vendue seule',
                  price: CurrencyFormatter.local(context, _p.sellingPriceHtg),
                  onTap: () => _select(MeasureKind.each),
                ),
              ],
              if (_p.options.isNotEmpty) ...[
                const SizedBox(height: AppConstants.spacing16),
                for (final group in _p.options) ...[
                  Text(
                    group.required ? '${group.name} · obligatoire' : group.name,
                    style: AppTextStyles.body(
                      color: ink,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in group.choices)
                        FilterChip(
                          label: Text(
                            choice.priceDeltaHtg == 0
                                ? choice.name
                                : '${choice.name} · +${CurrencyFormatter.local(context, choice.priceDeltaHtg)}',
                          ),
                          selected:
                              _selected[group.id]?.contains(choice.id) ?? false,
                          onSelected: (_) => _toggle(group, choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Nombre', style: AppTextStyles.body(color: ink)),
                  const Spacer(),
                  _Step(
                    icon: Icons.remove,
                    onTap: _qty > 1 ? () => setState(() => _qty--) : null,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$_qty',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        color: ink,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _Step(
                    icon: Icons.add,
                    onTap: room == null || _qty < room
                        ? () => setState(() => _qty++)
                        : null,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppTextStyles.caption(color: AppColors.boldRed),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AppButton(
            label: unit == null
                ? 'Choisissez'
                : 'Ajouter · ${CurrencyFormatter.local(context, unit * _qty)}',
            onPressed: unit == null ? null : _confirm,
            compact: true,
          ),
        ),
      ],
    );
  }

  String? _widthPrice(BuildContext context) {
    final choice = _widthChoice;
    if (choice == null) return null;
    if (choice.rejectReason(
          mode: _p.saleMode,
          minWidth: _p.minWidth,
          maxWidth: _p.rollWidth,
        ) !=
        null) {
      return null;
    }
    return CurrencyFormatter.local(context, _p.priceFor(choice));
  }

  String _lengthDetail(BuildContext context) {
    final price = CurrencyFormatter.local(context, _p.sellingPriceHtg);
    if (_p.rollWidth >= 1) {
      return '$price par pouce · minimum ${_p.minWidth} po · maximum ${_p.rollWidth} po';
    }
    return '$price par pouce · minimum ${_p.minWidth} po';
  }

  String _widthSentence(BuildContext context) {
    final width = int.tryParse(_widthCtrl.text.trim());
    if (width == null || width < 1)
      return 'Le total est le prix par pouce × la longueur.';
    if (_p.rollWidth >= 1 && width > _p.rollWidth) {
      return 'Le maximum est ${_p.rollWidth} po.';
    }
    if (width < _p.minWidth) return 'Le minimum est ${_p.minWidth} po.';
    final total = _p.sellingPriceHtg * width;
    return '$width po × ${CurrencyFormatter.local(context, _p.sellingPriceHtg)} = ${CurrencyFormatter.local(context, total)}';
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
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.title,
    required this.detail,
    required this.onTap,
    this.price,
  });

  final bool selected;
  final String title;
  final String detail;
  final String? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.28 : 0.1)
          : (isDark ? AppColors.darkBackground : const Color(0xFFF7F5F0)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primaryBlue : AppColors.darkGray,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body(
                        color: ink,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      detail,
                      style: AppTextStyles.caption(color: AppColors.darkGray),
                    ),
                  ],
                ),
              ),
              if (price != null)
                Text(
                  price!,
                  style: AppTextStyles.body(
                    color: AppColors.primaryBlue,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
    );
  }
}

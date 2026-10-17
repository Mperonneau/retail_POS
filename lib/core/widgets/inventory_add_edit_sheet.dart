import 'package:flutter/material.dart';

import '../mock/mock_restaurant_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/input_formatters.dart';
import 'app_button.dart';
import 'form_field_error.dart';

/// Shared add/edit inventory item form with unit select and type (Food/Drink).
class InventoryAddEditSheet extends StatefulWidget {
  final MockInventoryItem? existing;
  final void Function(MockInventoryItem) onSave;

  const InventoryAddEditSheet({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<InventoryAddEditSheet> createState() => _InventoryAddEditSheetState();
}

class _InventoryAddEditSheetState extends State<InventoryAddEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _minCtrl;
  late String _unit;
  late String _category;
  late InventoryItemType _type;

  String? _errorName;

  final _categories = [
    'Épicerie sèche',
    'Viande',
    'Fruits de mer',
    'Fruits et légumes',
    'Boissons',
    'Garde-manger',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _qtyCtrl = TextEditingController(text: e?.quantity.toString() ?? '');
    _minCtrl = TextEditingController(
        text: e?.minThreshold.toStringAsFixed(0) ?? '');
    _unit = (e != null && inventoryUnitOptions.contains(e.unit)) ? e.unit : 'KG';
    _category = (e != null && _categories.contains(e.category)) ? e.category : 'Épicerie sèche';
    _type = e?.type ?? InventoryItemType.food;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _errorName = null);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorName = 'Le nom de l\'article est obligatoire');
      return;
    }
    widget.onSave(MockInventoryItem(
      id: widget.existing?.id ?? 0,
      name: name,
      unit: _unit,
      quantity: double.tryParse(_qtyCtrl.text) ?? 0,
      minThreshold: double.tryParse(_minCtrl.text) ?? 0,
      category: _category,
      type: _type,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        top: AppConstants.spacing24,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'Ajouter un article' : 'Modifier l\'article',
              style: AppTextStyles.h2(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nom de l\'article *',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
              ),
            ),
            FormFieldError(text: _errorName),
            const SizedBox(height: AppConstants.spacing12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: InputDecoration(
                    labelText: 'Unité',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  items: inventoryUnitOptions
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _unit = v!),
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ),
            ]),
            const SizedBox(height: AppConstants.spacing12),
            DropdownButtonFormField<InventoryItemType>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
              ),
              items: const [
                DropdownMenuItem(value: InventoryItemType.food, child: Text('Cuisine')),
                DropdownMenuItem(value: InventoryItemType.drink, child: Text('Boisson')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: AppConstants.spacing12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quantité actuelle',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  decoration: InputDecoration(
                    labelText: 'Min Threshold',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                ),
              ),
            ]),
            const SizedBox(height: AppConstants.spacing24),
            AppButton(
              label: widget.existing == null ? 'Enregistrer l\'article' : 'Mettre à jour l\'article',
              onPressed: _save,
            ),
            const SizedBox(height: AppConstants.spacing8),
          ],
        ),
      ),
    );
  }
}

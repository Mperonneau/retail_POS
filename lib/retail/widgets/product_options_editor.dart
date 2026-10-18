import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../models/product_option.dart';

class ProductChoiceDraft {
  ProductChoiceDraft({String name = '', String price = '', String? id})
      : id = id ?? newProductOptionId('choix'),
        nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price);

  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

class ProductOptionDraft {
  ProductOptionDraft({
    required this.kind,
    required String name,
    required this.required,
    required this.multiple,
    List<ProductChoiceDraft>? choices,
    String? id,
  })  : id = id ?? newProductOptionId('option'),
        nameCtrl = TextEditingController(text: name),
        choices = choices ?? [];

  final String id;
  final ProductOptionKind kind;
  final TextEditingController nameCtrl;
  bool required;
  bool multiple;
  final List<ProductChoiceDraft> choices;

  factory ProductOptionDraft.fromPreset(ProductOptionPreset preset) {
    return ProductOptionDraft(
      kind: preset.kind,
      name: preset.kind == ProductOptionKind.other ? '' : preset.label,
      required: preset.required,
      multiple: preset.multiple,
      choices: [
        for (final suggestion in preset.suggestions)
          ProductChoiceDraft(name: suggestion),
      ],
    );
  }

  factory ProductOptionDraft.fromGroup(ProductOptionGroup group) {
    return ProductOptionDraft(
      id: group.id,
      kind: group.kind,
      name: group.name,
      required: group.required,
      multiple: group.multiple,
      choices: [
        for (final choice in group.choices)
          ProductChoiceDraft(
            id: choice.id,
            name: choice.name,
            price: choice.priceDeltaHtg == 0
                ? ''
                : choice.priceDeltaHtg.toStringAsFixed(
                    choice.priceDeltaHtg == choice.priceDeltaHtg.roundToDouble()
                        ? 0
                        : 2,
                  ),
          ),
      ],
    );
  }

  void dispose() {
    nameCtrl.dispose();
    for (final choice in choices) {
      choice.dispose();
    }
  }

  ProductOptionGroup? toGroup() {
    final name = nameCtrl.text.trim();
    final built = <ProductOptionChoice>[];
    for (final choice in choices) {
      final choiceName = choice.nameCtrl.text.trim();
      if (choiceName.isEmpty) continue;
      final raw = choice.priceCtrl.text.trim().replaceAll(',', '.');
      final price = raw.isEmpty ? 0.0 : double.tryParse(raw) ?? 0;
      built.add(ProductOptionChoice(
        id: choice.id,
        name: choiceName,
        priceDeltaHtg: price < 0 ? 0 : price,
      ));
    }
    if (name.isEmpty || built.isEmpty) return null;
    return ProductOptionGroup(
      id: id,
      name: name,
      kind: kind,
      required: required,
      multiple: multiple,
      choices: built,
    );
  }
}

class ProductOptionsEditor extends StatelessWidget {
  const ProductOptionsEditor({
    super.key,
    required this.drafts,
    required this.onChanged,
    this.errorText,
  });

  final List<ProductOptionDraft> drafts;
  final VoidCallback onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE4E7EC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Options',
          style: AppTextStyles.body(color: ink).copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Choix ou suppléments pour ce produit. Facultatif.',
          style: AppTextStyles.caption(color: muted),
        ),
        const SizedBox(height: AppConstants.spacing12),
        for (final draft in drafts) ...[
          _OptionCard(
            draft: draft,
            border: border,
            ink: ink,
            muted: muted,
            isDark: isDark,
            onChanged: onChanged,
            onRemove: () {
              draft.dispose();
              drafts.remove(draft);
              onChanged();
            },
          ),
          const SizedBox(height: AppConstants.spacing8),
        ],
        if (errorText != null) ...[
          Text(
            errorText!,
            style: AppTextStyles.caption(color: AppColors.boldRed),
          ),
          const SizedBox(height: AppConstants.spacing8),
        ],
        AppButton(
          label: 'Ajouter une option',
          icon: Icons.add,
          variant: AppButtonVariant.secondary,
          compact: true,
          fullWidth: false,
          onPressed: () => _pickPreset(context),
        ),
      ],
    );
  }

  Future<void> _pickPreset(BuildContext context) async {
    final preset = await showDialog<ProductOptionPreset>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
          title: Text('Ajouter une option', style: AppTextStyles.h3(color: ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in ProductOptionPreset.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(preset.label),
                  subtitle: Text(
                    preset.required ? 'Obligatoire par défaut' : 'Facultatif',
                    style: AppTextStyles.caption(),
                  ),
                  onTap: () => Navigator.pop(ctx, preset),
                ),
            ],
          ),
        );
      },
    );
    if (preset == null) return;
    drafts.add(ProductOptionDraft.fromPreset(preset));
    onChanged();
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.draft,
    required this.border,
    required this.ink,
    required this.muted,
    required this.isDark,
    required this.onChanged,
    required this.onRemove,
  });

  final ProductOptionDraft draft;
  final Color border;
  final Color ink;
  final Color muted;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final nameLocked = draft.kind != ProductOptionKind.other;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: nameLocked
                    ? Text(
                        draft.nameCtrl.text,
                        style: AppTextStyles.body(color: ink).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : TextField(
                        controller: draft.nameCtrl,
                        decoration: _dec('Nom de l’option'),
                        onChanged: (_) => onChanged(),
                      ),
              ),
              IconButton(
                tooltip: 'Retirer l’option',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: AppColors.boldRed),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Un seul choix'),
                selected: !draft.multiple,
                onSelected: (_) {
                  draft.multiple = false;
                  onChanged();
                },
              ),
              ChoiceChip(
                label: const Text('Plusieurs choix'),
                selected: draft.multiple,
                onSelected: (_) {
                  draft.multiple = true;
                  onChanged();
                },
              ),
              FilterChip(
                label: const Text('Obligatoire'),
                selected: draft.required,
                onSelected: (value) {
                  draft.required = value;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing8),
          for (final choice in draft.choices) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: choice.nameCtrl,
                    decoration: _dec('Choix'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: choice.priceCtrl,
                    decoration: _dec('+ HTG'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: InputFormatters.decimalAmount,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer le choix',
                  onPressed: () {
                    choice.dispose();
                    draft.choices.remove(choice);
                    onChanged();
                  },
                  icon: Icon(Icons.close, size: 18, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          TextButton.icon(
            onPressed: () {
              draft.choices.add(ProductChoiceDraft());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ajouter un choix'),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      ),
    );
  }
}

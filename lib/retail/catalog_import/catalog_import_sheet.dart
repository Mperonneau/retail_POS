import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/catalog_price_helpers.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_close_button.dart';
import '../models/product_option.dart';
import 'catalog_file.dart';
import 'catalog_files.dart';
import 'catalog_import_client.dart';

/// Upload a price list, review the products Claude extracted, then add them.
class CatalogImportSheet extends ConsumerStatefulWidget {
  const CatalogImportSheet({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<CatalogImportSheet> createState() => _CatalogImportSheetState();
}

class _EditableItem {
  _EditableItem(this.source, {required this.include})
    : name = TextEditingController(text: source.name),
      price = TextEditingController(
        text: source.priceHtg > 0 ? '${source.priceHtg}' : '',
      );

  final CatalogDraftItem source;
  final TextEditingController name;
  final TextEditingController price;
  bool include;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _EditableCategory {
  _EditableCategory(this.name, this.items);

  final TextEditingController name;
  final List<_EditableItem> items;

  void dispose() {
    name.dispose();
    for (final item in items) {
      item.dispose();
    }
  }
}

class _CatalogImportSheetState extends ConsumerState<CatalogImportSheet> {
  final _client = CatalogImportClient();
  final _note = TextEditingController();
  final _rate = TextEditingController();
  final _files = <CatalogFile>[];
  var _currency = 'htg';
  var _sending = false;
  String? _formError;
  String _progress = '';
  String? _failed;
  List<_EditableCategory> _categories = [];
  List<CatalogReportLine> _report = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final rate = ref.read(currencySettingsProvider).usdToLocalRate;
    if (rate > 0) _rate.text = rate.round().toString();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _note.dispose();
    _rate.dispose();
    for (final category in _categories) {
      category.dispose();
    }
    super.dispose();
  }

  bool get _needsRate => _currency == 'usd' || _currency == 'mixed';

  Future<void> _pick() async {
    final picked = await pickCatalogFiles();
    if (!mounted) return;
    setState(() {
      _formError = picked.error;
      for (final file in picked.files) {
        if (_files.length >= 6) break;
        final same = _files.any(
          (existing) =>
              existing.name == file.name &&
              existing.bytes.length == file.bytes.length,
        );
        if (!same) _files.add(file);
      }
    });
  }

  Future<void> _start() async {
    if (_files.isEmpty) {
      setState(() => _formError = 'Ajoutez au moins un document.');
      return;
    }
    final rate = int.tryParse(_rate.text.trim()) ?? 0;
    if (_needsRate && rate <= 0) {
      setState(
        () => _formError = 'Indiquez combien de gourdes valent 1 dollar.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _formError = null;
      _failed = null;
      _progress = 'Envoi du document…';
    });
    try {
      final id = await _client.start(
        files: _files,
        ownerNote: _note.text.trim(),
        currencyMode: _currency,
        usdRate: _needsRate ? rate : 0,
      );
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh(id));
      await _refresh(id);
    } on CatalogImportException catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _formError = error.message;
        });
      }
    }
  }

  Future<void> _refresh(String id) async {
    try {
      final job = await _client.fetch(id);
      if (!mounted) return;
      if (!job.isDone) {
        setState(
          () => _progress = job.progress.isEmpty
              ? 'Lecture du document…'
              : job.progress,
        );
        return;
      }
      _poll?.cancel();
      if (job.status == 'failed') {
        setState(() {
          _sending = false;
          _failed = job.error.isEmpty
              ? 'L\'analyse a échoué. Réessayez.'
              : job.error;
        });
        return;
      }
      _showDraft(job);
    } on CatalogImportException catch (error) {
      if (!mounted) return;
      _poll?.cancel();
      setState(() {
        _sending = false;
        _failed = error.message;
      });
    }
  }

  void _showDraft(CatalogJob job) {
    final known = {
      for (final product in ref.read(mockProductsProvider))
        product.name.trim().toLowerCase(),
    };
    for (final category in _categories) {
      category.dispose();
    }
    setState(() {
      _sending = false;
      _report = job.report;
      _categories = [
        for (final category in job.categories)
          _EditableCategory(TextEditingController(text: category.name), [
            for (final item in category.items)
              _EditableItem(
                item,
                include:
                    item.name.trim().isNotEmpty &&
                    !known.contains(item.name.trim().toLowerCase()),
              ),
          ]),
      ];
    });
  }

  int get _selectedCount => _categories.fold<int>(0, (sum, category) {
    return sum +
        category.items
            .where((item) => item.include && item.name.text.trim().isNotEmpty)
            .length;
  });

  void _commit() {
    final settings = ref.read(currencySettingsProvider);
    final notifier = ref.read(mockProductsProvider.notifier);
    var added = 0;
    for (final category in _categories) {
      final categoryName = category.name.text.trim().isEmpty
          ? 'Autre'
          : category.name.text.trim();
      for (final item in category.items) {
        if (!item.include) continue;
        final name = item.name.text.trim();
        final price = double.tryParse(
          item.price.text.replaceAll(',', '.').trim(),
        );
        if (name.isEmpty || price == null || price < 0) continue;
        final priced = CatalogPriceLogic.commitParsed(settings, price);
        notifier.add(
          MockProduct(
            id: 0,
            name: name,
            category: categoryName,
            priceHtg: priced.priceHtg,
            priceUsd: priced.priceUsd,
            costHtg: item.source.costHtg.toDouble(),
            stockQuantity: item.source.stock ?? 0,
            minStock: 0,
            barcode: item.source.barcode.isEmpty ? null : item.source.barcode,
            description: item.source.description,
            trackStock: item.source.stock != null,
            stockUnit: item.source.unit.isEmpty ? 'u' : item.source.unit,
            options: [
              for (final group in item.source.groups)
                if (group.choices.isNotEmpty)
                  ProductOptionGroup(
                    id: newProductOptionId('ia'),
                    name: group.name,
                    kind: switch (group.kind) {
                      'size' => ProductOptionKind.size,
                      'color' => ProductOptionKind.color,
                      'extra' => ProductOptionKind.extra,
                      _ => ProductOptionKind.other,
                    },
                    required: group.requiredChoice,
                    multiple: group.multiple,
                    choices: [
                      for (final choice in group.choices)
                        ProductOptionChoice(
                          id: newProductOptionId('choix'),
                          name: choice.name,
                          priceDeltaHtg: choice.priceDeltaHtg.toDouble(),
                        ),
                    ],
                  ),
            ],
          ),
        );
        added++;
      }
    }
    if (added == 0) {
      setState(() => _formError = 'Cochez au moins un produit avec un prix.');
      return;
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Importer des produits',
                  style: AppTextStyles.h2(color: ink),
                ),
              ),
              AppCloseButton(onPressed: widget.onClose),
            ],
          ),
        ),
        Expanded(
          child: _categories.isNotEmpty
              ? _review(isDark, ink)
              : _sending
              ? _working(ink)
              : _form(isDark, ink),
        ),
      ],
    );
  }

  Widget _form(bool isDark, Color ink) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(
          'Photo, PDF, Excel, CSV ou Word. L\'assistant prépare le catalogue. Rien n\'est ajouté avant votre confirmation.',
          style: AppTextStyles.body(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Choisir des documents'),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in _files)
                InputChip(
                  label: Text(file.name, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _files.remove(file)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Note pour l\'assistant (facultatif)',
            hintText:
                'Exemple : prix en dollars, ignorer la page des promotions.',
          ),
        ),
        const SizedBox(height: 8),
        Text('Devise des prix', style: AppTextStyles.caption(color: ink)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final choice in const [
              ('htg', 'HTG'),
              ('usd', 'USD'),
              ('mixed', 'Mixte'),
            ])
              ChoiceChip(
                label: Text(choice.$2),
                selected: _currency == choice.$1,
                onSelected: (_) => setState(() => _currency = choice.$1),
              ),
          ],
        ),
        if (_needsRate) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _rate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '1 USD en HTG'),
          ),
        ],
        if (_failed != null) ...[
          const SizedBox(height: 12),
          Text(_failed!, style: AppTextStyles.body(color: AppColors.boldRed)),
        ],
        if (_formError != null) ...[
          const SizedBox(height: 12),
          Text(
            _formError!,
            style: AppTextStyles.body(color: AppColors.boldRed),
          ),
        ],
        const SizedBox(height: 20),
        AppButton(
          label: 'Analyser',
          icon: Icons.auto_awesome_outlined,
          onPressed: _start,
        ),
      ],
    );
  }

  Widget _working(Color ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _progress,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _review(bool isDark, Color ink) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              if (_report.isNotEmpty) ...[
                for (final line in _report)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line.message,
                      style: AppTextStyles.caption(
                        color: line.severity == 'error'
                            ? AppColors.boldRed
                            : line.severity == 'warning'
                            ? AppColors.amber
                            : muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              for (final category in _categories) ...[
                TextField(
                  controller: category.name,
                  style: AppTextStyles.h3(color: ink),
                  decoration: const InputDecoration(labelText: 'Rayon'),
                ),
                const SizedBox(height: 8),
                for (final item in category.items)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: item.include,
                    onChanged: (value) =>
                        setState(() => item.include = value ?? false),
                    title: TextField(
                      controller: item.name,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Produit',
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: item.price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Prix HTG',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (_formError != null)
                Text(
                  _formError!,
                  style: AppTextStyles.body(color: AppColors.boldRed),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: AppButton(
            label:
                'Ajouter $_selectedCount produit${_selectedCount == 1 ? '' : 's'}',
            icon: Icons.check_rounded,
            onPressed: _selectedCount == 0 ? null : _commit,
          ),
        ),
      ],
    );
  }
}

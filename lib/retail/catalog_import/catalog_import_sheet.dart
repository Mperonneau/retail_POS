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
import '../models/sale_measure.dart';
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

String _caughtLine(CatalogDraftItem item) {
  final parts = <String>[];
  if (item.barcode.isNotEmpty) parts.add(item.barcode);
  if (item.costHtg > 0) parts.add('Achat ${item.costHtg} HTG');
  if (item.stock != null) parts.add('Stock ${item.stock} ${item.unit}');
  if (item.discountPercent > 0) parts.add('Rabais ${item.discountPercent} %');
  if (item.groups.isNotEmpty) {
    parts.add(item.groups.map((group) => group.name).join(', '));
  }
  return parts.join(' · ');
}

class _EditableItem {
  _EditableItem(this.source, {required this.include})
    : name = TextEditingController(text: source.name),
      price = TextEditingController(
        text: source.priceHtg > 0 ? '${source.priceHtg}' : '',
      ),
      description = TextEditingController(text: source.description),
      rollPrice = TextEditingController(
        text: source.rollPriceHtg > 0 ? '${source.rollPriceHtg}' : '',
      ),
      rollWidth = TextEditingController(
        text: source.rollWidth > 0 ? '${source.rollWidth}' : '',
      ),
      minWidth = TextEditingController(
        text: source.minWidth > 0 ? '${source.minWidth}' : '',
      ),
      casePrice = TextEditingController(
        text: source.casePriceHtg > 0 ? '${source.casePriceHtg}' : '',
      ),
      unitsPerCase = TextEditingController(
        text: source.unitsPerCase > 0 ? '${source.unitsPerCase}' : '',
      );

  final CatalogDraftItem source;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController description;
  final TextEditingController rollPrice;
  final TextEditingController rollWidth;
  final TextEditingController minWidth;
  final TextEditingController casePrice;
  final TextEditingController unitsPerCase;
  bool include;

  void dispose() {
    name.dispose();
    price.dispose();
    description.dispose();
    rollPrice.dispose();
    rollWidth.dispose();
    minWidth.dispose();
    casePrice.dispose();
    unitsPerCase.dispose();
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
    try {
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
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _formError = 'Impossible d\'ajouter le document. Réessayez.',
      );
    }
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
      final known = <String>[];
      for (final product in ref.read(mockProductsProvider)) {
        final name = product.category.trim();
        if (name.isNotEmpty && !known.contains(name)) known.add(name);
      }
      final id = await _client.start(
        files: _files,
        ownerNote: _note.text.trim(),
        currencyMode: _currency,
        usdRate: _needsRate ? rate : 0,
        knownCategories: known,
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
    final pending = <MockProduct>[];
    for (final category in _categories) {
      final categoryName = category.name.text.trim().isEmpty
          ? 'Autre'
          : category.name.text.trim();
      for (final item in category.items) {
        final name = item.name.text.trim();
        if (!item.include || name.isEmpty) continue;
        final price = double.tryParse(
          item.price.text.replaceAll(',', '.').trim(),
        );
        if (price == null || price <= 0) {
          setState(() => _formError = '« $name » : indiquez le prix.');
          return;
        }
        final mode = saleModeFromWire(item.source.saleMode);
        final priced = CatalogPriceLogic.commitParsed(settings, price);
        var rollPriceHtg = 0.0;
        var rollPriceUsd = 0.0;
        var casePriceHtg = 0.0;
        var casePriceUsd = 0.0;
        var rollWidth = 0;
        var minWidth = 0;
        var unitsPerCase = 0;
        if (mode == SaleMode.roll) {
          final rollParsed = double.tryParse(
            item.rollPrice.text.replaceAll(',', '.').trim(),
          );
          rollWidth = int.tryParse(item.rollWidth.text.trim()) ?? 0;
          minWidth = int.tryParse(item.minWidth.text.trim()) ?? 0;
          if (rollParsed == null || rollParsed <= 0) {
            setState(
              () => _formError =
                  '« $name » : indiquez le prix de la longueur entière.',
            );
            return;
          }
          if (rollWidth < 1) {
            setState(
              () => _formError =
                  '« $name » : indiquez la longueur entière en pouces.',
            );
            return;
          }
          if (minWidth < 1 || minWidth > rollWidth) {
            setState(
              () => _formError =
                  '« $name » : le minimum doit être entre 1 et $rollWidth po.',
            );
            return;
          }
          final rolled = CatalogPriceLogic.commitParsed(settings, rollParsed);
          rollPriceHtg = rolled.priceHtg;
          rollPriceUsd = rolled.priceUsd;
        } else if (mode == SaleMode.pack) {
          final caseParsed = double.tryParse(
            item.casePrice.text.replaceAll(',', '.').trim(),
          );
          unitsPerCase = int.tryParse(item.unitsPerCase.text.trim()) ?? 0;
          if (caseParsed == null || caseParsed <= 0) {
            setState(
              () => _formError = '« $name » : indiquez le prix de la caisse.',
            );
            return;
          }
          if (unitsPerCase < 2) {
            setState(
              () => _formError =
                  '« $name » : une caisse contient au moins 2 unités.',
            );
            return;
          }
          final packed = CatalogPriceLogic.commitParsed(settings, caseParsed);
          casePriceHtg = packed.priceHtg;
          casePriceUsd = packed.priceUsd;
        }
        final unit = item.source.unit;
        final description = item.description.text.trim();
        pending.add(
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
            description: description.length > 600
                ? description.substring(0, 600)
                : description,
            discountPercent: item.source.discountPercent,
            trackStock: item.source.stock != null,
            stockUnit: unit == 'kg' || unit == 'L' || unit == 'paquet'
                ? unit
                : 'u',
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
            saleMode: mode,
            rollPriceHtg: rollPriceHtg,
            rollPriceUsd: rollPriceUsd,
            minWidth: minWidth,
            rollWidth: rollWidth,
            casePriceHtg: casePriceHtg,
            casePriceUsd: casePriceUsd,
            unitsPerCase: unitsPerCase,
          ),
        );
      }
    }
    if (pending.isEmpty) {
      setState(() => _formError = 'Cochez au moins un produit avec un prix.');
      return;
    }
    for (final product in pending) {
      notifier.add(product);
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
          'Photo, PDF, Excel, CSV ou Word. L\'assistant reprend le nom, le prix, le type de prix, la description et le rayon. Un rayon nouveau reste une catégorie de ce magasin. Rien n\'est ajouté avant votre confirmation.',
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

  Widget _itemFields(_EditableItem item, Color muted) {
    final mode = item.source.saleMode;
    final caught = _caughtLine(item.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          switch (mode) {
            'roll' => 'Au pouce',
            'case' => 'Caisse',
            _ => 'Prix simple',
          },
          style: AppTextStyles.caption(color: muted),
        ),
        TextField(
          controller: item.name,
          decoration: const InputDecoration(isDense: true, labelText: 'Produit'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: item.price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            labelText: switch (mode) {
              'roll' => 'Prix par pouce (HTG)',
              'case' => 'Prix d\'une unité (HTG)',
              _ => 'Prix HTG',
            },
          ),
        ),
        if (mode == 'roll') ...[
          const SizedBox(height: 8),
          TextField(
            controller: item.rollPrice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Prix de la longueur entière',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: item.rollWidth,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Longueur entière (po)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: item.minWidth,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Minimum (po)',
            ),
          ),
        ],
        if (mode == 'case') ...[
          const SizedBox(height: 8),
          TextField(
            controller: item.casePrice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Prix d\'une caisse',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: item.unitsPerCase,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Unités dans la caisse',
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: item.description,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Description',
          ),
        ),
        if (caught.isNotEmpty)
          Text(caught, style: AppTextStyles.caption(color: muted)),
      ],
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: item.include,
                          onChanged: (value) =>
                              setState(() => item.include = value ?? false),
                        ),
                        Expanded(child: _itemFields(item, muted)),
                      ],
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

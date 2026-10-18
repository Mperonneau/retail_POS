import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/supplier_category_taxonomy.dart';
import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_close_button.dart';

/// Single product category: type-ahead (saved + taxonomy), free text, browse domains.
class ProductCategoryField extends ConsumerStatefulWidget {
  const ProductCategoryField({
    super.key,
    required this.category,
    required this.onCategoryChanged,
    this.errorText,
  });

  final String category;
  final ValueChanged<String> onCategoryChanged;
  final String? errorText;

  @override
  ConsumerState<ProductCategoryField> createState() =>
      _ProductCategoryFieldState();
}

class _ProductCategoryFieldState extends ConsumerState<ProductCategoryField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  bool _showSuggestions = false;
  Timer? _hideSuggestionsTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.category);
    _focusNode = FocusNode();
    _ctrl.addListener(_onInputChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ProductCategoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category &&
        widget.category != _ctrl.text &&
        !_focusNode.hasFocus) {
      _ctrl.text = widget.category;
    }
  }

  @override
  void dispose() {
    _hideSuggestionsTimer?.cancel();
    _ctrl.removeListener(_onInputChanged);
    _focusNode.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    widget.onCategoryChanged(_ctrl.text);
    setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    _hideSuggestionsTimer?.cancel();
    if (_focusNode.hasFocus) {
      setState(() => _showSuggestions = true);
      return;
    }
    _hideSuggestionsTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (!_focusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  void _pickSuggestion(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    _hideSuggestionsTimer?.cancel();
    _ctrl.text = t;
    _focusNode.unfocus();
    if (mounted) {
      setState(() => _showSuggestions = false);
    }
    widget.onCategoryChanged(t);
  }

  void _tryCommitTyped() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _hideSuggestionsTimer?.cancel();
    _focusNode.unfocus();
    if (mounted) setState(() => _showSuggestions = false);
    widget.onCategoryChanged(t);
  }

  List<String> _savedSorted(List<MockProduct> products) {
    final set = <String>{};
    for (final p in products) {
      if (p.category.trim().isNotEmpty) set.add(p.category.trim());
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Set<String> _taxonomySet() => SupplierCategoryTaxonomy.allCategories.toSet();

  /// Empty query: all saved categories (capped). If none, seed from taxonomy.
  List<String> _suggestionsEmptyQuery(
    List<String> savedSorted,
    Set<String> taxonomy,
  ) {
    const cap = 48;
    if (savedSorted.isNotEmpty) {
      return savedSorted.take(cap).toList();
    }
    final fromTax = taxonomy.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return fromTax.take(cap).toList();
  }

  List<String> _suggestionsFiltered(
    String query,
    List<String> savedSorted,
    Set<String> taxonomy,
  ) {
    final ql = query.trim().toLowerCase();
    if (ql.isEmpty) {
      return _suggestionsEmptyQuery(savedSorted, taxonomy);
    }
    final seen = <String>{};
    final candidates = <String>[];

    void consider(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      final k = t.toLowerCase();
      if (seen.contains(k)) return;
      if (!k.contains(ql)) return;
      seen.add(k);
      candidates.add(t);
    }

    for (final s in savedSorted) {
      consider(s);
    }
    for (final s in taxonomy) {
      consider(s);
    }

    candidates.sort((a, b) {
      final al = a.toLowerCase();
      final bl = b.toLowerCase();
      final as = al.startsWith(ql);
      final bs = bl.startsWith(ql);
      if (as != bs) return as ? -1 : 1;
      return a.compareTo(b);
    });
    return candidates.take(24).toList();
  }

  Future<void> _openBrowse() async {
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ProductCategoryBrowseDialogBody(
        currentCategory: _ctrl.text.trim(),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    _ctrl.text = picked;
    widget.onCategoryChanged(picked);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final fill = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final linkColor = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final borderDecoration = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );

    final products = ref.watch(mockProductsProvider);
    final suggestions = _suggestionsFiltered(
      _ctrl.text,
      _savedSorted(products),
      _taxonomySet(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Catégorie *',
            hintText: 'Saisissez ou choisissez une suggestion',
            filled: true,
            fillColor: fill,
            border: borderDecoration,
            errorText: widget.errorText,
            errorMaxLines: 2,
            suffixIcon: _ctrl.text.trim().isNotEmpty
                ? IconButton(
                    tooltip: 'Appliquer la catégorie',
                    onPressed: _tryCommitTyped,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(
                      width: AppConstants.minTouchTarget,
                      height: AppConstants.buttonHeight,
                    ),
                    icon: Icon(
                      Icons.check_circle_outline_rounded,
                      color: linkColor,
                    ),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            suffixIconConstraints: BoxConstraints.tightFor(
              height: AppConstants.buttonHeight,
              width: AppConstants.minTouchTarget,
            ),
          ),
          onSubmitted: (_) => _tryCommitTyped(),
        ),
        if (_showSuggestions && suggestions.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spacing4),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.white,
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.darkGray.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? AppColors.darkBorder
                      : AppColors.darkGray.withValues(alpha: 0.15),
                ),
                itemBuilder: (context, index) {
                  final option = suggestions[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing12,
                      vertical: 2,
                    ),
                    title: Text(
                      option,
                      style: AppTextStyles.body(color: textPrimary)
                          .copyWith(fontSize: 13),
                    ),
                    trailing: Icon(
                      Icons.north_west_rounded,
                      size: 16,
                      color: isDark
                          ? AppColors.skyBlue.withValues(alpha: 0.6)
                          : AppColors.primaryBlue.withValues(alpha: 0.5),
                    ),
                    onTap: () => _pickSuggestion(option),
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: AppConstants.spacing4),
        GestureDetector(
          onTap: _openBrowse,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 13,
                color: linkColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                'Parcourir les catégories',
                style: AppTextStyles.caption(color: linkColor).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single-select: pick domain → pick one category → returns label.
class _ProductCategoryBrowseDialogBody extends StatefulWidget {
  const _ProductCategoryBrowseDialogBody({required this.currentCategory});

  final String currentCategory;

  @override
  State<_ProductCategoryBrowseDialogBody> createState() =>
      _ProductCategoryBrowseDialogBodyState();
}

class _ProductCategoryBrowseDialogBodyState
    extends State<_ProductCategoryBrowseDialogBody> {
  SupplierCategoryDomain? _domain;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final maxW = mq.size.width >= AppConstants.mobileBreakpoint
        ? 520.0
        : mq.size.width - 32;
    final maxH = mq.size.height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing24,
      ),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      ),
      child: SizedBox(
        width: maxW,
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing16,
                AppConstants.spacing16,
                AppConstants.spacing8,
                AppConstants.spacing8,
              ),
              child: Row(
                children: [
                  if (_domain != null)
                    IconButton(
                      tooltip: 'Retour',
                      onPressed: () {
                        setState(() {
                          _domain = null;
                          _searchCtrl.clear();
                        });
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: Text(
                      _domain == null
                          ? 'Choisissez une famille de produits'
                          : _domain!.label,
                      style: AppTextStyles.h2(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            if (_domain != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing16,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans cette zone…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 22),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkBackground
                        : AppColors.warmOffWhite,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
            ],
            Expanded(
              child: _domain == null
                  ? _BrowseDomainList(
                      isDark: isDark,
                      onPick: (d) {
                        setState(() {
                          _domain = d;
                          _searchCtrl.clear();
                        });
                      },
                    )
                  : _BrowseCategoryListSingle(
                      domain: _domain!,
                      searchQuery: _searchCtrl.text,
                      currentLower: widget.currentCategory.trim().toLowerCase(),
                      onSelect: (label) => Navigator.pop(context, label),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: Text(
                _domain == null
                    ? 'Choisissez une famille, puis une catégorie pour ce produit.'
                    : 'Touchez une catégorie pour la sélectionner.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseDomainList extends StatelessWidget {
  const _BrowseDomainList({
    required this.isDark,
    required this.onPick,
  });

  final bool isDark;
  final void Function(SupplierCategoryDomain d) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        0,
        AppConstants.spacing16,
        AppConstants.spacing8,
      ),
      itemCount: SupplierCategoryTaxonomy.domains.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppConstants.spacing8),
      itemBuilder: (context, i) {
        final d = SupplierCategoryTaxonomy.domains[i];
        return Material(
          color: isDark
              ? AppColors.darkBackground.withValues(alpha: 0.5)
              : AppColors.lightBlue.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            onTap: () => onPick(d),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16,
                vertical: AppConstants.spacing16,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.label,
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.categories.length} types de produits',
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrowseCategoryListSingle extends StatelessWidget {
  const _BrowseCategoryListSingle({
    required this.domain,
    required this.searchQuery,
    required this.currentLower,
    required this.onSelect,
  });

  final SupplierCategoryDomain domain;
  final String searchQuery;
  final String currentLower;
  final void Function(String label) onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = searchQuery.trim().toLowerCase();
    final items = domain.categories.where((c) {
      if (q.isEmpty) return true;
      return c.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacing24),
          child: Text(
            'Aucune catégorie ne correspond à votre recherche.',
            style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        0,
        AppConstants.spacing16,
        AppConstants.spacing8,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final label = items[i];
        final isCurrent =
            currentLower.isNotEmpty && label.toLowerCase() == currentLower;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing8,
            vertical: 0,
          ),
          title: Text(
            label,
            style: AppTextStyles.body(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
          ),
          trailing: Icon(
            isCurrent ? Icons.check_circle_rounded : Icons.add_circle_outline,
            color: isCurrent
                ? AppColors.deepGreen
                : (isDark ? AppColors.coolGray : AppColors.darkGray),
          ),
          onTap: () => onSelect(label),
        );
      },
    );
  }
}

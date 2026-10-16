import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/supplier_category_taxonomy.dart';
import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';

/// Product categories (types of products this supplier sells): field, chips, picker.
class SupplierCategoryField extends ConsumerStatefulWidget {
  const SupplierCategoryField({
    super.key,
    required this.categories,
    required this.onCategoriesChanged,
  });

  final List<String> categories;
  final ValueChanged<List<String>> onCategoriesChanged;

  @override
  ConsumerState<SupplierCategoryField> createState() =>
      _SupplierCategoryFieldState();
}

class _SupplierCategoryFieldState extends ConsumerState<SupplierCategoryField> {
  late final TextEditingController _inputCtrl;
  late final FocusNode _focusNode;
  bool _showSuggestions = false;
  Timer? _hideSuggestionsTimer;

  @override
  void initState() {
    super.initState();
    _inputCtrl = TextEditingController();
    _focusNode = FocusNode();
    _inputCtrl.addListener(_onInputChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _hideSuggestionsTimer?.cancel();
    _inputCtrl.removeListener(_onInputChanged);
    _focusNode.removeListener(_onFocusChanged);
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    _hideSuggestionsTimer?.cancel();
    if (_focusNode.hasFocus) {
      setState(() => _showSuggestions = true);
      return;
    }
    // Defer hiding so a tap on a suggestion can complete before the overlay is
    // removed (otherwise focus leaves the field first and the list vanishes).
    _hideSuggestionsTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (!_focusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  bool _hasCategoryInsensitive(String value) {
    final v = value.trim().toLowerCase();
    return widget.categories.any((c) => c.toLowerCase() == v);
  }

  /// Avoid updating parents during pointer / mouse-tracker dispatch (web/desktop),
  /// which can trigger `mouse_tracker.dart` assertions with overlays + chips.
  void _scheduleCategoriesChanged(List<String> next) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCategoriesChanged(next);
    });
  }

  void _addIfAbsent(String raw) {
    final t = raw.trim();
    if (t.isEmpty || _hasCategoryInsensitive(t)) return;
    _hideSuggestionsTimer?.cancel();
    _inputCtrl.clear();
    _focusNode.unfocus();
    if (mounted) {
      setState(() => _showSuggestions = false);
    }
    _scheduleCategoriesChanged([...widget.categories, t]);
  }

  void _remove(String cat) {
    _focusNode.unfocus();
    _scheduleCategoriesChanged(
      widget.categories.where((c) => c != cat).toList(),
    );
  }

  /// Seed + categories already used by other suppliers in the business.
  Set<String> _mergedSuggestionPool(List<MockSupplier> suppliers) {
    final pool = <String>{
      ...SupplierCategoryTaxonomy.allCategories,
    };
    for (final s in suppliers) {
      pool.addAll(s.categories);
    }
    return pool;
  }

  List<String> _filteredSuggestions(
    String query,
    Set<String> pool,
  ) {
    final selectedLower = widget.categories.map((c) => c.toLowerCase()).toSet();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final candidates = pool.where((s) {
      if (selectedLower.contains(s.toLowerCase())) return false;
      return s.toLowerCase().contains(q);
    }).toList();

    candidates.sort((a, b) {
      final al = a.toLowerCase();
      final bl = b.toLowerCase();
      final aStarts = al.startsWith(q);
      final bStarts = bl.startsWith(q);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.compareTo(b);
    });

    return candidates.take(24).toList();
  }

  Future<void> _openDomainPicker() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _SupplierCategoryDomainPicker(
        initialCategories: List<String>.from(widget.categories),
        onChanged: widget.onCategoriesChanged,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;
    final fill = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final borderDecoration = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );

    final pool = ref.watch(
      mockSuppliersProvider.select(
        (suppliers) => _mergedSuggestionPool(suppliers),
      ),
    );

    InputDecoration fieldDec(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: fill,
          border: borderDecoration,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Product categories',
                style: AppTextStyles.h3(
                  color: textPrimary,
                ),
              ),
            ),
            Tooltip(
              message:
                  'List the kinds of products this supplier sells (for example: '
                  'groceries, construction materials, beverages). This helps you '
                  'search and filter suppliers. You can add more than one.',
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text(
          'What kinds of products does this supplier sell? Pick from suggestions, '
          'browse by product area, or type your own — you can add several.',
          style: AppTextStyles.caption(color: textSecondary),
        ),
        const SizedBox(height: AppConstants.spacing12),
        if (widget.categories.isNotEmpty) ...[
          Wrap(
            spacing: AppConstants.spacing8,
            runSpacing: AppConstants.spacing8,
            children: widget.categories.map((cat) {
              return Chip(
                label: Text(
                  cat,
                  style: AppTextStyles.caption(),
                ),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => _remove(cat),
                backgroundColor: isDark
                    ? AppColors.primaryBlue.withValues(alpha: 0.2)
                    : AppColors.lightBlue,
                side: BorderSide(
                  color: isDark
                      ? AppColors.skyBlue.withValues(alpha: 0.3)
                      : AppColors.primaryBlue.withValues(alpha: 0.2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
          const SizedBox(height: AppConstants.spacing12),
        ],
        Builder(
          builder: (context) {
            final suggestions = _filteredSuggestions(_inputCtrl.text, pool);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: fieldDec(
                    'Search or add product category',
                    hint: 'Type to see product types',
                  ).copyWith(
                    suffixIcon: IconButton(
                      tooltip: 'Add product category',
                      onPressed: _tryAddFromText,
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: isDark ? AppColors.skyBlue : AppColors.deepGreen,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _tryAddFromText(),
                ),
                if (_showSuggestions && suggestions.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.white,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.darkGray.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.darkGray.withValues(alpha: 0.2),
                        ),
                        itemBuilder: (context, index) {
                          final option = suggestions[index];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.spacing12,
                            ),
                            title: Text(
                              option,
                              style: AppTextStyles.body(color: textPrimary),
                            ),
                            trailing: Icon(
                              Icons.add_circle_outline_rounded,
                              size: 18,
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ),
                            onTap: () => _addIfAbsent(option),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppConstants.spacing4),
                GestureDetector(
                  onTap: _openDomainPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 13,
                        color:
                            (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                                .withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Browse product categories',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                          decoration: TextDecoration.underline,
                          decorationColor: (isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _tryAddFromText() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty) return;
    _addIfAbsent(t);
  }
}

class _SupplierCategoryDomainPicker extends StatefulWidget {
  const _SupplierCategoryDomainPicker({
    required this.initialCategories,
    required this.onChanged,
  });

  final List<String> initialCategories;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_SupplierCategoryDomainPicker> createState() =>
      _SupplierCategoryDomainPickerState();
}

class _SupplierCategoryDomainPickerState
    extends State<_SupplierCategoryDomainPicker> {
  SupplierCategoryDomain? _domain;
  final _searchCtrl = TextEditingController();
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initialCategories);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleCategory(String label) {
    final lower = label.toLowerCase();
    final idx = _selected.indexWhere((c) => c.toLowerCase() == lower);
    setState(() {
      if (idx >= 0) {
        _selected = [..._selected]..removeAt(idx);
      } else {
        _selected = [..._selected, label];
      }
    });
    final copy = List<String>.from(_selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onChanged(copy);
    });
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
                      tooltip: 'Back',
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
                          ? 'Choose a product area'
                          : _domain!.label,
                      style: AppTextStyles.h2(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
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
                    hintText: 'Search product categories…',
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
                  ? _DomainList(
                      isDark: isDark,
                      onPick: (d) {
                        setState(() {
                          _domain = d;
                          _searchCtrl.clear();
                        });
                      },
                    )
                  : _CategoryList(
                      domain: _domain!,
                      searchQuery: _searchCtrl.text,
                      alreadySelected: _selected,
                      onTap: _toggleCategory,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: Text(
                'Tap a product category to add or remove it for this supplier.',
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

class _DomainList extends StatelessWidget {
  const _DomainList({
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
                          '${d.categories.length} product types',
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

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.domain,
    required this.searchQuery,
    required this.alreadySelected,
    required this.onTap,
  });

  final SupplierCategoryDomain domain;
  final String searchQuery;
  final List<String> alreadySelected;
  final void Function(String label) onTap;

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
            'No product categories match your search.',
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
        final selected = alreadySelected.any(
          (s) => s.toLowerCase() == label.toLowerCase(),
        );
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
            selected ? Icons.check_circle : Icons.add_circle_outline,
            color: selected
                ? AppColors.deepGreen
                : (isDark ? AppColors.coolGray : AppColors.darkGray),
          ),
          onTap: () => onTap(label),
        );
      },
    );
  }
}

import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/utils/catalog_price_helpers.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/barcode_scan_screen.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/form_field_error.dart';
import '../../core/widgets/status_badge.dart';
import '../widgets/product_category_field.dart';

const int _kProductPageSize = 15;

double _productGridAspectRatio(int crossAxisCount) {
  switch (crossAxisCount) {
    case 3:
      return 4.6;
    case 2:
      return 4.2;
    default:
      return 4.3;
  }
}

class ProductManagement extends ConsumerStatefulWidget {
  const ProductManagement({super.key});

  @override
  ConsumerState<ProductManagement> createState() => _ProductManagementState();
}

class _ProductManagementState extends ConsumerState<ProductManagement> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allProducts = ref.watch(mockProductsProvider);

    final categoryNames = allProducts.map((p) => p.category).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final filtered = allProducts.where((p) {
      if (_categoryFilter != null && p.category != _categoryFilter) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          (p.barcode != null && p.barcode!.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final totalPages = max(
      1,
      (filtered.length + _kProductPageSize - 1) ~/ _kProductPageSize,
    );
    final safePage = min(_currentPage, totalPages);
    if (safePage != _currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentPage = safePage);
      });
    }
    final pageStart = (safePage - 1) * _kProductPageSize;
    final pageItems =
        filtered.skip(pageStart).take(_kProductPageSize).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < AppConstants.mobileBreakpoint;
          final pad = EdgeInsets.symmetric(
            horizontal: narrow ? AppConstants.spacing16 : AppConstants.spacing24,
            vertical: AppConstants.spacing24,
          );

          final countBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.25)
                  : AppColors.lightBlue.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? AppColors.skyBlue.withValues(alpha: 0.35)
                    : AppColors.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              '${allProducts.length} produit${allProducts.length == 1 ? '' : 's'}',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          );
          final addButton = AppButton(
            label: 'Ajouter un produit',
            onPressed: () => _showProductSheet(context, null),
            icon: Icons.add,
            fullWidth: false,
            compact: true,
            width: narrow ? null : 148,
          );

          final listSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Produits',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h1(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    addButton,
                  ],
                )
              else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Produits',
                            style: AppTextStyles.h1(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing12),
                        countBadge,
                      ],
                    ),
                  ),
                  addButton,
                  if (filtered.isNotEmpty && !narrow) ...[
                    const SizedBox(width: AppConstants.spacing8),
                    _ProductTopPagination(
                      isDark: isDark,
                      currentPage: safePage,
                      totalPages: totalPages,
                      onPrevious: safePage > 1
                          ? () => setState(() => _currentPage = safePage - 1)
                          : null,
                      onNext: safePage < totalPages
                          ? () => setState(() => _currentPage = safePage + 1)
                          : null,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
              Row(
                children: [
                  if (narrow) ...[
                    countBadge,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'Gérez le catalogue, les prix et les stocks.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing16),
              _ProductFilterRow(
                isDark: isDark,
                narrow: narrow,
                searchController: _searchCtrl,
                onSearchChanged: (v) => setState(() {
                  _query = v;
                  _currentPage = 1;
                }),
                categories: categoryNames,
                categoryFilter: _categoryFilter,
                onCategoryChanged: (v) => setState(() {
                  _categoryFilter = v;
                  _currentPage = 1;
                }),
              ),
              const SizedBox(height: AppConstants.spacing12),
              AppCard(
                padding: EdgeInsets.zero,
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppConstants.spacing24),
                        child: allProducts.isEmpty
                            ? const EmptyState(
                                icon: Icons.inventory_outlined,
                                title: 'Aucun produit',
                                message:
                                    'Ajoutez votre premier produit pour commencer.',
                              )
                            : Text(
                                'Aucun produit ne correspond à votre recherche.',
                                style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                      )
                    : LayoutBuilder(
                        builder: (context, inner) {
                          final cw = inner.maxWidth;
                          final int crossAxisCount;
                          if (cw >= AppConstants.mobileBreakpoint) {
                            crossAxisCount = 3;
                          } else {
                            crossAxisCount = 1;
                          }

                          if (crossAxisCount == 1) {
                            return Column(
                              children: pageItems.asMap().entries.map((e) {
                                final i = e.key;
                                final p = e.value;
                                return Column(
                                  children: [
                                    _ProductListTile(
                                      product: p,
                                      isDark: isDark,
                                      onMoreTap: () =>
                                          _showOptions(context, p),
                                    ),
                                    if (i < pageItems.length - 1)
                                      const Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                      ),
                                  ],
                                );
                              }).toList(),
                            );
                          }

                          return Padding(
                            padding:
                                const EdgeInsets.all(AppConstants.spacing12),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: AppConstants.spacing12,
                                mainAxisSpacing: AppConstants.spacing12,
                                childAspectRatio: _productGridAspectRatio(
                                  crossAxisCount,
                                ),
                              ),
                              itemCount: pageItems.length,
                              itemBuilder: (context, i) {
                                final p = pageItems[i];
                                return _ProductGridTile(
                                  product: p,
                                  isDark: isDark,
                                  onMoreTap: () => _showOptions(context, p),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              if (narrow && filtered.isNotEmpty && totalPages > 1) ...[
                const SizedBox(height: AppConstants.spacing16),
                Align(
                  alignment: Alignment.centerRight,
                  child: _ProductTopPagination(
                    isDark: isDark,
                    currentPage: safePage,
                    totalPages: totalPages,
                    onPrevious: safePage > 1
                        ? () => setState(() => _currentPage = safePage - 1)
                        : null,
                    onNext: safePage < totalPages
                        ? () => setState(() => _currentPage = safePage + 1)
                        : null,
                  ),
                ),
              ],
            ],
          );

          return SingleChildScrollView(
            padding: pad,
            child: listSection,
          );
        },
      ),
    );
  }

  void _showProductSheet(BuildContext context, MockProduct? existing) {
    showAppBottomSheet(
      context: context,
      child: _AddProductSheet(
        existing: existing,
        onSave: (product) {
          if (existing == null) {
            ref.read(mockProductsProvider.notifier).add(product);
          } else {
            ref.read(mockProductsProvider.notifier).update(product);
          }
        },
      ),
    );
  }

  void _showOptions(BuildContext context, MockProduct product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showAppBottomSheet(
      context: context,
      isScrollControlled: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ),
              title: const Text('Modifier le produit'),
              onTap: () {
                Navigator.pop(context);
                _showProductSheet(context, product);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.boldRed),
              title: const Text(
                'Supprimer le produit',
                style: TextStyle(color: AppColors.boldRed),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, product);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, MockProduct product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le produit'),
        content: Text('Retirer « ${product.name} » de l\'inventaire ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mockProductsProvider.notifier).remove(product.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${product.name} retiré'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text(
              'Supprimer',
              style: TextStyle(color: AppColors.boldRed),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pagination ───────────────────────────────────────────────────────────────

class _ProductTopPagination extends StatelessWidget {
  const _ProductTopPagination({
    required this.isDark,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isDark;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final disabled = isDark ? AppColors.coolGray : AppColors.darkGray;
    final active = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Page précédente',
          onPressed: onPrevious,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(
            minWidth: AppConstants.minTouchTarget,
            minHeight: AppConstants.minTouchTarget,
          ),
          icon: Icon(
            Icons.chevron_left_rounded,
            color: onPrevious == null ? disabled : active,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '$currentPage / $totalPages',
            style: AppTextStyles.caption(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Page suivante',
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(
            minWidth: AppConstants.minTouchTarget,
            minHeight: AppConstants.minTouchTarget,
          ),
          icon: Icon(
            Icons.chevron_right_rounded,
            color: onNext == null ? disabled : active,
          ),
        ),
      ],
    );
  }
}

// ─── Filter row ───────────────────────────────────────────────────────────────

class _ProductFilterRow extends StatelessWidget {
  const _ProductFilterRow({
    required this.isDark,
    required this.narrow,
    required this.searchController,
    required this.onSearchChanged,
    required this.categories,
    required this.categoryFilter,
    required this.onCategoryChanged,
  });

  final bool isDark;
  final bool narrow;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<String> categories;
  final String? categoryFilter;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? AppColors.darkBorder
        : AppColors.darkGray.withValues(alpha: 0.25);
    final fill = isDark ? AppColors.darkSurface : AppColors.white;
    final active = categoryFilter != null;

    final clearIconColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final searchField = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      style: AppTextStyles.body(
        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
      ).copyWith(fontSize: narrow ? 13 : null),
      decoration: InputDecoration(
        hintText: narrow
            ? 'Nom, catégorie, code-barres…'
            : 'Rechercher par nom, catégorie, code-barres…',
        hintStyle: narrow
            ? AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              )
            : null,
        prefixIcon: Icon(Icons.search_rounded, size: narrow ? 16 : 20),
        prefixIconConstraints: BoxConstraints(
          minWidth: narrow ? 34 : 40,
          minHeight: narrow ? 32 : 40,
        ),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Effacer la recherche',
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
                icon: Icon(
                  Icons.close_rounded,
                  size: narrow ? 16 : 20,
                  color: clearIconColor,
                ),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(32, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            : null,
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 10 : 16,
          vertical: narrow ? 6 : 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
      ),
    );

    final catChip = _ProductCategoryFilterButton(
      isDark: isDark,
      fill: fill,
      borderColor: borderColor,
      active: active,
      label: categoryFilter ??
          (narrow ? 'Catégories' : 'Toutes les catégories'),
      compact: narrow,
      categoryFilter: categoryFilter,
      categories: categories,
      onChanged: onCategoryChanged,
    );

    if (narrow) {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 156),
            child: catChip,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        catChip,
        const SizedBox(width: AppConstants.spacing12),
        Expanded(child: searchField),
      ],
    );
  }
}

class _ProductCategoryFilterButton extends StatelessWidget {
  const _ProductCategoryFilterButton({
    required this.isDark,
    required this.fill,
    required this.borderColor,
    required this.active,
    required this.label,
    this.compact = false,
    required this.categoryFilter,
    required this.categories,
    required this.onChanged,
  });

  final bool isDark;
  final Color fill;
  final Color borderColor;
  final bool active;
  final String label;
  final bool compact;
  final String? categoryFilter;
  final List<String> categories;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primaryBlue;
    final bg =
        active ? activeColor.withValues(alpha: isDark ? 0.25 : 0.08) : fill;
    final border = active
        ? activeColor.withValues(alpha: isDark ? 0.55 : 0.4)
        : borderColor;
    final textColor = active
        ? (isDark ? AppColors.skyBlue : activeColor)
        : (isDark ? AppColors.coolGray : AppColors.darkGray);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _openMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 9,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 16, color: textColor),
            const SizedBox(width: 6),
            if (compact)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: textColor).copyWith(
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              )
            else
              Text(
                label,
                style: AppTextStyles.caption(color: textColor).copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: textColor),
            if (active) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(Icons.close_rounded, size: 14, color: textColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openMenu(BuildContext context) {
    final items = <PopupMenuEntry<String?>>[
      PopupMenuItem<String?>(
        value: null,
        child: Row(
          children: [
            Icon(
              Icons.select_all_rounded,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
            const SizedBox(width: 8),
            Text(
              'Toutes les catégories',
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 4),
      ...categories.map(
        (c) => PopupMenuItem<String?>(
          value: c,
          child: Row(
            children: [
              Icon(
                categoryFilter == c
                    ? Icons.check_rounded
                    : Icons.category_outlined,
                size: 16,
                color: categoryFilter == c
                    ? AppColors.primaryBlue
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 8),
              Text(
                c,
                style: AppTextStyles.body(
                  color: categoryFilter == c
                      ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                      : (isDark ? AppColors.warmWhite : AppColors.nearBlack),
                ).copyWith(
                  fontWeight:
                      categoryFilter == c ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String?>(
      context: context,
      color: isDark ? AppColors.darkSurface : AppColors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        side: BorderSide(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.darkGray.withValues(alpha: 0.15),
        ),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: items,
    ).then((val) {
      if (!context.mounted) return;
      onChanged(val);
    });
  }
}

// ─── Grid tile ────────────────────────────────────────────────────────────────

class _ProductGridTile extends StatelessWidget {
  const _ProductGridTile({
    required this.product,
    required this.isDark,
    required this.onMoreTap,
  });

  final MockProduct product;
  final bool isDark;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.45)
        : AppColors.lightBlue.withValues(alpha: 0.35);
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final usd = CurrencyFormatter.usdEquivalentOrNull(
      context,
      product.priceHtg,
    );

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onMoreTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Content block – shrinks to fit its children.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: name (left) + price (right)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(color: textPrimary)
                                .copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          CurrencyFormatter.local(context, product.priceHtg),
                          style: AppTextStyles.price(color: textPrimary)
                              .copyWith(fontSize: 11.5, height: 1.15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    // Row 2: category · margin (left) + USD hint (right)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            '${product.category} · ${product.margin.toStringAsFixed(0)} % marge',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ).copyWith(fontSize: 9.5, height: 1.1),
                          ),
                        ),
                        if (usd != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            CurrencyFormatter.usdEquivalent(
                              context,
                              product.priceHtg,
                            ),
                            style: AppTextStyles.caption().copyWith(
                              fontSize: 8.5,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Row 3: stock badges
                    Row(
                      children: [
                        if (product.isLowStock)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: StatusBadge(
                              status: StatusType.lowStock,
                              customLabel: 'Low',
                              compact: true,
                              micro: true,
                            ),
                          ),
                        StatusBadge(
                          status: StatusType.active,
                          customLabel: '${product.stockQuantity} u.',
                          compact: true,
                          micro: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Overflow menu – aligned to center via the Row's crossAxisAlignment.
              SizedBox(
                width: 28,
                height: 28,
                child: InkWell(
                  onTap: onMoreTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Center(
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 16,
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.isDark,
    required this.onMoreTap,
  });

  final MockProduct product;
  final bool isDark;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final usd = CurrencyFormatter.usdEquivalentOrNull(
      context,
      product.priceHtg,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onMoreTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: textPrimary).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${product.category} · ${product.margin.toStringAsFixed(0)} % marge',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ).copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    CurrencyFormatter.local(context, product.priceHtg),
                    style: AppTextStyles.price(color: textPrimary)
                        .copyWith(fontSize: 12),
                  ),
                  if (usd != null)
                    Text(
                      CurrencyFormatter.usdEquivalent(
                        context,
                        product.priceHtg,
                      ),
                      style: AppTextStyles.caption().copyWith(fontSize: 9),
                    ),
                  StatusBadge(
                    status: product.isLowStock
                        ? StatusType.lowStock
                        : StatusType.active,
                    customLabel: product.isLowStock
                        ? 'Bas ${product.stockQuantity}'
                        : '${product.stockQuantity}',
                    compact: true,
                    micro: true,
                  ),
                ],
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 16),
                onPressed: onMoreTap,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProductSheet extends ConsumerStatefulWidget {
  final MockProduct? existing;
  final void Function(MockProduct) onSave;

  const _AddProductSheet({this.existing, required this.onSave});

  @override
  ConsumerState<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<_AddProductSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _barcodeCtrl;
  late String _category;

  String? _errorName;
  String? _errorCategory;
  String? _errorPrice;
  String? _errorStockInitial;

  void _onPriceChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl = TextEditingController();
    _priceCtrl.addListener(_onPriceChanged);
    _costCtrl = TextEditingController(text: e?.costHtg.toStringAsFixed(0) ?? '');
    _stockCtrl = TextEditingController(text: e?.stockQuantity.toString() ?? '');
    _minCtrl = TextEditingController(text: e?.minStock.toString() ?? '');
    _barcodeCtrl = TextEditingController(text: e?.barcode ?? '');
    _category = e?.category ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ex = widget.existing;
      if (ex != null) {
        final s = ref.read(currencySettingsProvider);
        _priceCtrl.text = CatalogPriceLogic.initialPriceFieldText(
          s,
          ex.priceHtg,
          ex.priceUsd,
        );
      }
    });
  }

  @override
  void dispose() {
    _priceCtrl.removeListener(_onPriceChanged);
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _minCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    if (!BarcodeScanScreen.isSupported) return;
    final code = await BarcodeScanScreen.showModal(context);
    if (!mounted || code == null || code.isEmpty) return;
    setState(() => _barcodeCtrl.text = code);
  }

  void _save() {
    setState(() {
      _errorName = null;
      _errorCategory = null;
      _errorPrice = null;
      _errorStockInitial = null;
    });
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorName = 'Le nom du produit est obligatoire');
      return;
    }
    final cat = _category.trim();
    if (cat.isEmpty) {
      setState(() => _errorCategory = 'La catégorie est obligatoire');
      return;
    }
    final s = ref.read(currencySettingsProvider);
    final priceRaw = _priceCtrl.text.trim();
    final priceParsed = double.tryParse(priceRaw);
    if (priceRaw.isEmpty || priceParsed == null || priceParsed <= 0) {
      setState(() => _errorPrice = 'Le prix est obligatoire');
      return;
    }
    final stockRaw = _stockCtrl.text.trim();
    if (stockRaw.isEmpty) {
      setState(() => _errorStockInitial = 'Le stock initial est obligatoire');
      return;
    }
    final stockQty = int.tryParse(stockRaw);
    if (stockQty == null || stockQty < 0) {
      setState(
        () => _errorStockInitial = 'Saisissez un nombre entier valide (0 ou plus)',
      );
      return;
    }
    final p = CatalogPriceLogic.commitParsed(s, priceParsed);
    final barcode = _barcodeCtrl.text.trim();
    widget.onSave(MockProduct(
      id: widget.existing?.id ?? 0,
      name: name,
      category: cat,
      priceHtg: p.priceHtg,
      priceUsd: p.priceUsd,
      costHtg: double.tryParse(_costCtrl.text) ?? 0,
      stockQuantity: stockQty,
      minStock: int.tryParse(_minCtrl.text) ?? 0,
      barcode: barcode.isEmpty ? null : barcode,
      active: widget.existing?.active ?? true,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(currencySettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final helperColor =
        (isDark ? AppColors.coolGray : AppColors.darkGray).withValues(alpha: 0.65);
    final helperStyle = TextStyle(
      fontSize: 11,
      height: 1.4,
      color: helperColor,
    );
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );

    InputDecoration fieldDec({
      required String label,
      String? prefixText,
      String? helperText,
      int helperMaxLines = 2,
      String? errorText,
      Widget? prefixIcon,
      Widget? suffixIcon,
    }) =>
        InputDecoration(
          labelText: label,
          prefixText: prefixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          helperText: helperText,
          helperMaxLines: helperMaxLines,
          helperStyle: helperText != null ? helperStyle : null,
          errorText: errorText,
          errorMaxLines: 2,
          border: outlineBorder,
        );

    final scrollableFields = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing24,
        AppConstants.spacing24,
        AppConstants.spacing24,
        AppConstants.spacing16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Ajouter un produit' : 'Modifier le produit',
            style: AppTextStyles.h2(color: textPrimary),
          ),
          const SizedBox(height: AppConstants.spacing20),
          TextField(
            controller: _nameCtrl,
            decoration: fieldDec(label: 'Nom du produit *'),
          ),
          FormFieldError(text: _errorName),
          const SizedBox(height: AppConstants.spacing16),
          ProductCategoryField(
            category: _category,
            errorText: _errorCategory,
            onCategoryChanged: (c) => setState(() {
              _category = c;
              _errorCategory = null;
            }),
          ),
          const SizedBox(height: AppConstants.spacing16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  decoration: fieldDec(
                    label: '${CatalogPriceLogic.priceFieldLabel(s)} *',
                    prefixText: CatalogPriceLogic.priceFieldPrefix(s),
                    errorText: _errorPrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  onChanged: (_) {
                    if (_errorPrice != null) {
                      setState(() => _errorPrice = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  decoration: fieldDec(
                    label: 'Cost (${s.localCurrencyCode})',
                    prefixText: '${s.localCurrencyCode} ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                ),
              ),
            ],
          ),
          if (CatalogPriceLogic.priceHintText(context, s, _priceCtrl.text) !=
              null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                CatalogPriceLogic.priceHintText(context, s, _priceCtrl.text)!,
                style: helperStyle,
              ),
            ),
          const SizedBox(height: AppConstants.spacing16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _stockCtrl,
                  decoration: fieldDec(
                    label: 'Stock initial *',
                    helperText:
                        'Unités en stock au moment d\'ajouter ce produit.',
                    errorText: _errorStockInitial,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: InputFormatters.digitsOnly,
                  onChanged: (_) {
                    if (_errorStockInitial != null) {
                      setState(() => _errorStockInitial = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  decoration: fieldDec(
                    label: 'Stock minimum',
                    helperText: 'Signale un stock bas à ce seuil ou en dessous.',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: InputFormatters.digitsOnly,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          TextField(
            controller: _barcodeCtrl,
            decoration: fieldDec(
              label: 'Code-barres (facultatif)',
              helperText:
                  'Saisissez le code de l\'étiquette, ou utilisez le scanner '
                  'pour le lire avec la caméra.',
              suffixIcon: BarcodeScanScreen.isSupported
                  ? IconButton(
                      icon: const Icon(Icons.document_scanner_outlined, size: 22),
                      tooltip: 'Scanner le code-barres',
                      onPressed: _openBarcodeScanner,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppConstants.spacing8),
        ],
      ),
    );

    final h = AppConstants.buttonHeightCompact;
    Widget actionRow() => Padding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacing24,
            AppConstants.spacing8,
            AppConstants.spacing24,
            MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: AppButton(
                  label: widget.existing == null
                      ? 'Enregistrer le produit'
                      : 'Mettre à jour le produit',
                  onPressed: _save,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: SizedBox(
                  height: h,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(double.infinity, h),
                      maximumSize: Size(double.infinity, h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusButton,
                        ),
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
              ),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: scrollableFields),
        const Divider(height: 1),
        actionRow(),
      ],
    );
  }
}

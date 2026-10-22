import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../widgets/category_filter_button.dart';
import '../widgets/retail_product_inventory_panel.dart';

const int _kInventoryPageSize = 15;

/// Width/height ratio for each grid cell (higher = shorter cards).
/// Tuned so tiles fit content without excess vertical padding.
double _inventoryGridAspectRatio(int crossAxisCount) {
  switch (crossAxisCount) {
    case 3:
      return 5.6;
    case 2:
      return 4.8;
    default:
      return 4.2;
  }
}

class RetailInventoryScreen extends ConsumerStatefulWidget {
  const RetailInventoryScreen({super.key});

  @override
  ConsumerState<RetailInventoryScreen> createState() =>
      _RetailInventoryScreenState();
}

class _RetailInventoryScreenState extends ConsumerState<RetailInventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// `null` = all categories.
  String? _categoryFilter;
  int _currentPage = 1;
  int? _selectedProductId;
  bool _drawerOpen = false;
  Timer? _drawerCloseTimer;

  @override
  void dispose() {
    _drawerCloseTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openDetailSheet(MockProduct product) {
    showRetailProductInventorySheet(context, product);
  }

  void _openDrawer(MockProduct product) {
    _drawerCloseTimer?.cancel();
    setState(() {
      _selectedProductId = product.id;
      _drawerOpen = true;
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _drawerCloseTimer?.cancel();
    _drawerCloseTimer = Timer(AppConstants.animNormal, () {
      if (!mounted) return;
      setState(() => _selectedProductId = null);
      _drawerCloseTimer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final products = ref.watch(mockProductsProvider);
    final categories = products.map((p) => p.category).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final filtered = products.where((p) {
      if (_categoryFilter != null && p.category != _categoryFilter) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();

    final lowStockItems = products.fold<int>(
      0,
      (n, p) => n + (p.isLowStock ? 1 : 0),
    );
    final filteredSorted = [...filtered]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final totalPages = max(
      1,
      (filteredSorted.length + _kInventoryPageSize - 1) ~/ _kInventoryPageSize,
    );
    final safePage = min(_currentPage, totalPages);
    if (safePage != _currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentPage = safePage);
      });
    }
    final pageStart = (safePage - 1) * _kInventoryPageSize;
    final pageItems = filteredSorted
        .skip(pageStart)
        .take(_kInventoryPageSize)
        .toList();

    MockProduct? selected;
    if (_selectedProductId != null) {
      for (final p in products) {
        if (p.id == _selectedProductId) {
          selected = p;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Use full window width so the drawer still opens when the sidebar shrinks the content area.
          final useSideDrawer =
              MediaQuery.sizeOf(context).width >= AppConstants.mobileBreakpoint;
          final pad = EdgeInsets.symmetric(
            horizontal: constraints.maxWidth < AppConstants.mobileBreakpoint
                ? AppConstants.spacing16
                : AppConstants.spacing24,
            vertical: AppConstants.spacing24,
          );

          final panelW = AppConstants.retailInventoryDetailPanelWidth(
            constraints.maxWidth,
          );

          final listSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Inventaire',
                            style: AppTextStyles.h1(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primaryBlue.withValues(alpha: 0.25)
                                : AppColors.lightBlue.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.skyBlue.withValues(alpha: 0.35)
                                  : AppColors.primaryBlue.withValues(
                                      alpha: 0.2,
                                    ),
                            ),
                          ),
                          child: Text(
                            '${products.length} produits',
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (filteredSorted.isNotEmpty &&
                      constraints.maxWidth >= AppConstants.mobileBreakpoint)
                    _InventoryTopPagination(
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
              ),
              const SizedBox(height: AppConstants.spacing8),
              Text(
                'Suivez le stock comme un compte : mouvements, réceptions et ventes du jour.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              if (lowStockItems > 0) ...[
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  '$lowStockItems sous le stock minimum',
                  style: AppTextStyles.caption(color: AppColors.amber),
                ),
              ],
              const SizedBox(height: AppConstants.spacing16),
              _InventoryFilterSearchRow(
                isDark: isDark,
                narrow: constraints.maxWidth < AppConstants.mobileBreakpoint,
                searchController: _searchCtrl,
                onSearchChanged: (v) => setState(() {
                  _query = v;
                  _currentPage = 1;
                }),
                categories: categories,
                categoryFilter: _categoryFilter,
                onCategoryChanged: (v) => setState(() {
                  _categoryFilter = v;
                  _currentPage = 1;
                }),
              ),
              const SizedBox(height: AppConstants.spacing12),
              AppCard(
                padding: EdgeInsets.zero,
                child: filteredSorted.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppConstants.spacing24),
                        child: Text(
                          'Aucun produit ne correspond à votre recherche.',
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final cw = constraints.maxWidth;
                          final crossAxisCount =
                              cw >= AppConstants.tabletBreakpoint
                              ? 3
                              : cw >= AppConstants.mobileBreakpoint
                              ? 2
                              : 1;
                          if (crossAxisCount == 1) {
                            return Column(
                              children: pageItems.asMap().entries.map((e) {
                                final i = e.key;
                                final p = e.value;
                                return Column(
                                  children: [
                                    _InventoryProductRow(
                                      product: p,
                                      isDark: isDark,
                                      selected:
                                          p.id == _selectedProductId &&
                                          _drawerOpen,
                                      onTap: () {
                                        if (useSideDrawer) {
                                          _openDrawer(p);
                                        } else {
                                          _openDetailSheet(p);
                                        }
                                      },
                                      onAddStock: () =>
                                          showRetailAddStockSheet(context, p),
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
                            padding: const EdgeInsets.all(
                              AppConstants.spacing12,
                            ),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: AppConstants.spacing12,
                                    mainAxisSpacing: AppConstants.spacing12,
                                    childAspectRatio: _inventoryGridAspectRatio(
                                      crossAxisCount,
                                    ),
                                  ),
                              itemCount: pageItems.length,
                              itemBuilder: (context, i) {
                                final p = pageItems[i];
                                return _InventoryProductGridTile(
                                  product: p,
                                  isDark: isDark,
                                  selected:
                                      p.id == _selectedProductId && _drawerOpen,
                                  onTap: () {
                                    if (useSideDrawer) {
                                      _openDrawer(p);
                                    } else {
                                      _openDetailSheet(p);
                                    }
                                  },
                                  onAddStock: () =>
                                      showRetailAddStockSheet(context, p),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              if (constraints.maxWidth < AppConstants.mobileBreakpoint &&
                  filteredSorted.isNotEmpty &&
                  totalPages > 1) ...[
                const SizedBox(height: AppConstants.spacing16),
                Align(
                  alignment: Alignment.centerRight,
                  child: _InventoryTopPagination(
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

          final scrollContent = SingleChildScrollView(
            padding: pad,
            child: listSection,
          );

          if (!useSideDrawer) {
            return scrollContent;
          }

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              scrollContent,
              if (selected != null) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_drawerOpen,
                    child: AnimatedOpacity(
                      opacity: _drawerOpen ? 1 : 0,
                      duration: AppConstants.animNormal,
                      curve: Curves.easeOut,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeDrawer,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: panelW,
                  child: SafeArea(
                    left: false,
                    child: AnimatedSlide(
                      offset: _drawerOpen ? Offset.zero : const Offset(1, 0),
                      duration: AppConstants.animNormal,
                      curve: Curves.easeOutCubic,
                      child: Material(
                        elevation: 16,
                        shadowColor: Colors.black.withValues(alpha: 0.35),
                        color: isDark ? AppColors.darkSurface : AppColors.white,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.darkGray.withValues(
                                        alpha: 0.25,
                                      ),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(
                              AppConstants.spacing24,
                            ),
                            child: RetailProductInventoryPanel(
                              product: selected,
                              embedded: true,
                              onClose: _closeDrawer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InventoryTopPagination extends StatelessWidget {
  const _InventoryTopPagination({
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

class _InventoryFilterSearchRow extends StatelessWidget {
  const _InventoryFilterSearchRow({
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

    final searchField = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Rechercher par nom ou catégorie…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 11,
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

    final catChip = CategoryFilterButton(
      isDark: isDark,
      fill: fill,
      borderColor: borderColor,
      expand: narrow,
      label: categoryFilter ?? 'Toutes les catégories',
      selected: categoryFilter,
      categories: categories,
      onChanged: onCategoryChanged,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          catChip,
          const SizedBox(height: AppConstants.spacing8),
          searchField,
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

class _InventoryProductGridTile extends StatelessWidget {
  const _InventoryProductGridTile({
    required this.product,
    required this.isDark,
    required this.selected,
    required this.onTap,
    required this.onAddStock,
  });

  final MockProduct product;
  final bool isDark;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.45)
        : AppColors.lightBlue.withValues(alpha: 0.35);

    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1)
          : cardBg,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: isDark
                        ? AppColors.primaryBlue.withValues(alpha: 0.35)
                        : AppColors.lightBlue,
                    child: Text(
                      product.name.isNotEmpty
                          ? product.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: AppTextStyles.h3(
                        color: isDark
                            ? AppColors.skyBlue
                            : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          product.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Text(
                              product.trackStock
                                  ? '${product.stockQuantity}'
                                  : 'Non suivi',
                              style:
                                  AppTextStyles.body(
                                    color: product.isLowStock
                                        ? AppColors.boldRed
                                        : (isDark
                                              ? AppColors.warmWhite
                                              : AppColors.nearBlack),
                                  ).copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                            const SizedBox(width: 6),
                            if (product.isLowStock)
                              const StatusBadge(
                                status: StatusType.lowStock,
                                compact: true,
                                micro: true,
                              )
                            else
                              Text(
                                'unités',
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.coolGray
                                      : AppColors.darkGray,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajouter du stock',
                    icon: const Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: AppColors.deepGreen,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: onAddStock,
                  ),
                  IconButton(
                    tooltip: 'Ouvrir les détails',
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                    onPressed: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryProductRow extends StatelessWidget {
  const _InventoryProductRow({
    required this.product,
    required this.isDark,
    required this.selected,
    required this.onTap,
    required this.onAddStock,
  });

  final MockProduct product;
  final bool isDark;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Container(
                color: selected
                    ? AppColors.primaryBlue.withValues(
                        alpha: isDark ? 0.18 : 0.08,
                      )
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isDark
                          ? AppColors.primaryBlue.withValues(alpha: 0.35)
                          : AppColors.lightBlue,
                      child: Text(
                        product.name.isNotEmpty
                            ? product.name.substring(0, 1).toUpperCase()
                            : '?',
                        style: AppTextStyles.h3(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            product.category,
                            style: AppTextStyles.caption(),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          product.trackStock
                              ? '${product.stockQuantity}'
                              : 'Non suivi',
                          style:
                              AppTextStyles.body(
                                color: product.isLowStock
                                    ? AppColors.boldRed
                                    : (isDark
                                          ? AppColors.warmWhite
                                          : AppColors.nearBlack),
                              ).copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                        ),
                        if (product.isLowStock)
                          const StatusBadge(
                            status: StatusType.lowStock,
                            compact: true,
                          )
                        else
                          Text(
                            'unités',
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Ajouter du stock',
              icon: const Icon(
                Icons.add_circle_outline,
                size: 22,
                color: AppColors.deepGreen,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: AppConstants.minTouchTarget,
                minHeight: AppConstants.minTouchTarget,
              ),
              onPressed: onAddStock,
            ),
          ),
        ],
      ),
    );
  }
}

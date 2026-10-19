import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/phone_field.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../widgets/supplier_category_field.dart';
import '../../core/widgets/app_close_button.dart';

const int _kSupplierPageSize = 15;

double _supplierGridAspectRatio(int crossAxisCount) {
  switch (crossAxisCount) {
    case 4:
      return 3.6;
    case 3:
      return 3.2;
    default:
      return 2.8;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class SupplierScreen extends ConsumerStatefulWidget {
  const SupplierScreen({super.key});

  @override
  ConsumerState<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends ConsumerState<SupplierScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  int _currentPage = 1;
  int? _selectedSupplierId;

  /// When true, the right panel shows the add-supplier form instead of details.
  bool _addSupplierPanel = false;
  bool _drawerOpen = false;
  Timer? _drawerCloseTimer;

  @override
  void dispose() {
    _drawerCloseTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openDrawer(MockSupplier supplier) {
    _drawerCloseTimer?.cancel();
    setState(() {
      _addSupplierPanel = false;
      _selectedSupplierId = supplier.id;
      _drawerOpen = true;
    });
  }

  void _openAddDrawer() {
    _drawerCloseTimer?.cancel();
    setState(() {
      _addSupplierPanel = true;
      _selectedSupplierId = null;
      _drawerOpen = true;
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _drawerCloseTimer?.cancel();
    _drawerCloseTimer = Timer(AppConstants.animNormal, () {
      if (!mounted) return;
      setState(() {
        _selectedSupplierId = null;
        _addSupplierPanel = false;
      });
      _drawerCloseTimer = null;
    });
  }

  void _openMobilePanel(MockSupplier supplier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (ctx, animation, secondary) {
          return Scaffold(
            backgroundColor:
                isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
            body: SafeArea(
              child: _SupplierDetailPanel(
                supplierId: supplier.id,
                embedded: false,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        },
        transitionsBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  void _openMobileAddPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (ctx, animation, secondary) {
          return Scaffold(
            backgroundColor:
                isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
            body: SafeArea(
              child: _AddEditSupplierForm(
                existing: null,
                embedded: true,
                onCancel: () => Navigator.of(ctx).pop(),
                onSuccess: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        },
        transitionsBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suppliers = ref.watch(mockSuppliersProvider);

    final allCategories = <String>{};
    for (final s in suppliers) {
      allCategories.addAll(s.categories);
    }
    final categories = allCategories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final filtered = suppliers.where((s) {
      if (_categoryFilter != null && !s.categories.contains(_categoryFilter)) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.phone.toLowerCase().contains(q) ||
          s.email.toLowerCase().contains(q) ||
          s.location.toLowerCase().contains(q) ||
          s.categories.any((c) => c.toLowerCase().contains(q)) ||
          s.contacts.any((c) => c.name.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final totalPages = max(
      1,
      (filtered.length + _kSupplierPageSize - 1) ~/ _kSupplierPageSize,
    );
    final safePage = min(_currentPage, totalPages);
    if (safePage != _currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentPage = safePage);
      });
    }
    final pageStart = (safePage - 1) * _kSupplierPageSize;
    final pageItems =
        filtered.skip(pageStart).take(_kSupplierPageSize).toList();

    MockSupplier? selected;
    if (_selectedSupplierId != null) {
      for (final s in suppliers) {
        if (s.id == _selectedSupplierId) {
          selected = s;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useSideDrawer =
              MediaQuery.sizeOf(context).width >= AppConstants.mobileBreakpoint;
          final pad = EdgeInsets.symmetric(
            horizontal: constraints.maxWidth < AppConstants.mobileBreakpoint
                ? AppConstants.spacing16
                : AppConstants.spacing24,
            vertical: AppConstants.spacing24,
          );
          final panelW =
              AppConstants.retailDetailSidePanelWidth(constraints.maxWidth);

          final listSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Fournisseurs',
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
                                  : AppColors.primaryBlue
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            '${suppliers.length} fournisseur${suppliers.length == 1 ? '' : 's'}',
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
                  AppButton(
                    label: 'Ajouter un fournisseur',
                    onPressed: () => useSideDrawer
                        ? _openAddDrawer()
                        : _openMobileAddPanel(),
                    icon: Icons.add,
                    fullWidth: false,
                    compact: true,
                    width: 148,
                  ),
                  if (filtered.isNotEmpty &&
                      constraints.maxWidth >= AppConstants.mobileBreakpoint) ...[
                    const SizedBox(width: AppConstants.spacing8),
                    _SupplierTopPagination(
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
              Text(
                'Gérez les fournisseurs, les contacts et les catégories qu\'ils fournissent.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              // ── Filter row ──────────────────────────────────────────────────
              _SupplierFilterRow(
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
              // ── Grid ────────────────────────────────────────────────────────
              AppCard(
                padding: EdgeInsets.zero,
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppConstants.spacing24),
                        child: Text(
                          'Aucun fournisseur ne correspond.',
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
                          if (cw >= AppConstants.tabletBreakpoint) {
                            crossAxisCount = 4;
                          } else if (cw >= AppConstants.mobileBreakpoint) {
                            crossAxisCount = 3;
                          } else {
                            crossAxisCount = 1;
                          }

                          if (crossAxisCount == 1) {
                            return Column(
                              children: pageItems.asMap().entries.map((e) {
                                final i = e.key;
                                final s = e.value;
                                return Column(
                                  children: [
                                    _SupplierListTile(
                                      supplier: s,
                                      isDark: isDark,
                                      selected: s.id == _selectedSupplierId &&
                                          _drawerOpen,
                                      onTap: () => useSideDrawer
                                          ? _openDrawer(s)
                                          : _openMobilePanel(s),
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
                                childAspectRatio:
                                    _supplierGridAspectRatio(crossAxisCount),
                              ),
                              itemCount: pageItems.length,
                              itemBuilder: (context, i) {
                                final s = pageItems[i];
                                return _SupplierGridTile(
                                  supplier: s,
                                  isDark: isDark,
                                  selected: s.id == _selectedSupplierId &&
                                      _drawerOpen,
                                  onTap: () => useSideDrawer
                                      ? _openDrawer(s)
                                      : _openMobilePanel(s),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              if (constraints.maxWidth < AppConstants.mobileBreakpoint &&
                  filtered.isNotEmpty &&
                  totalPages > 1) ...[
                const SizedBox(height: AppConstants.spacing16),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SupplierTopPagination(
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

          if (!useSideDrawer) return scrollContent;

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              scrollContent,
              if (selected != null || _addSupplierPanel) ...[
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
                                  : AppColors.darkGray.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        child: _addSupplierPanel
                            ? _AddEditSupplierForm(
                                existing: null,
                                embedded: true,
                                onCancel: _closeDrawer,
                                onSuccess: _closeDrawer,
                              )
                            : _SupplierDetailPanel(
                                supplierId: selected!.id,
                                embedded: true,
                                onClose: _closeDrawer,
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

// ─── Pagination ───────────────────────────────────────────────────────────────

class _SupplierTopPagination extends StatelessWidget {
  const _SupplierTopPagination({
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

class _SupplierFilterRow extends StatelessWidget {
  const _SupplierFilterRow({
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

    final searchField = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Rechercher par nom, catégorie, contact…',
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

    final catChip = _CategoryFilterButton(
      isDark: isDark,
      fill: fill,
      borderColor: borderColor,
      active: active,
      label: categoryFilter ?? 'Toutes les catégories',
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

class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    required this.isDark,
    required this.fill,
    required this.borderColor,
    required this.active,
    required this.label,
    required this.categories,
    required this.onChanged,
  });

  final bool isDark;
  final Color fill;
  final Color borderColor;
  final bool active;
  final String label;
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 16, color: textColor),
            const SizedBox(width: 6),
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
                c == label && active
                    ? Icons.check_rounded
                    : Icons.category_outlined,
                size: 16,
                color: c == label && active
                    ? AppColors.primaryBlue
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 8),
              Text(
                c,
                style: AppTextStyles.body(
                  color: c == label && active
                      ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                      : (isDark ? AppColors.warmWhite : AppColors.nearBlack),
                ).copyWith(
                  fontWeight: c == label && active ? FontWeight.w600 : null,
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
      if (val != null || val == null) onChanged(val);
    });
  }
}

// ─── Grid tile ────────────────────────────────────────────────────────────────

class _SupplierGridTile extends StatelessWidget {
  const _SupplierGridTile({
    required this.supplier,
    required this.isDark,
    required this.selected,
    required this.onTap,
  });

  final MockSupplier supplier;
  final bool isDark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.45)
        : AppColors.lightBlue.withValues(alpha: 0.35);

    final categoriesText = supplier.categories.isEmpty
        ? 'Aucune catégorie de produit'
        : supplier.categories.join(' · ');

    final phone = supplier.phone.isNotEmpty
        ? supplier.phone
        : (supplier.contacts.isNotEmpty ? supplier.contacts.first.phone : '');

    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1)
          : cardBg,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: isDark
                        ? AppColors.primaryBlue.withValues(alpha: 0.35)
                        : AppColors.lightBlue,
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: AppTextStyles.h3(
                        color:
                            isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          categoriesText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
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

// ─── List tile (mobile) ───────────────────────────────────────────────────────

class _SupplierListTile extends StatelessWidget {
  const _SupplierListTile({
    required this.supplier,
    required this.isDark,
    required this.selected,
    required this.onTap,
  });

  final MockSupplier supplier;
  final bool isDark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final categoriesText = supplier.categories.isEmpty
        ? 'Aucune catégorie de produit'
        : supplier.categories.join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected
              ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.18 : 0.08)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isDark
                    ? AppColors.primaryBlue.withValues(alpha: 0.35)
                    : AppColors.lightBlue,
                child: Text(
                  supplier.name.isNotEmpty
                      ? supplier.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: AppTextStyles.h3(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: AppTextStyles.body(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categoriesText,
                      style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (supplier.phone.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        supplier.phone,
                        style: AppTextStyles.caption(),
                      ),
                    ],
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
  }
}

// ─── Detail panel ─────────────────────────────────────────────────────────────

class _SupplierDetailPanel extends ConsumerStatefulWidget {
  const _SupplierDetailPanel({
    required this.supplierId,
    required this.embedded,
    this.onClose,
  });

  final int supplierId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<_SupplierDetailPanel> createState() =>
      _SupplierDetailPanelState();
}

class _SupplierDetailPanelState extends ConsumerState<_SupplierDetailPanel> {
  void _openEditSupplier(BuildContext context, MockSupplier supplier) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      child: _AddEditSupplierSheet(existing: supplier),
    );
  }

  void _openAddContact(BuildContext context, MockSupplier supplier) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      child: _ContactSheet(supplier: supplier),
    );
  }

  void _openEditContact(BuildContext context, MockSupplier supplier,
      MockSupplierContact contact) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      child: _ContactSheet(supplier: supplier, existing: contact),
    );
  }

  void _deleteContact(WidgetRef ref, MockSupplier supplier, String contactId) {
    final updated = supplier.copyWith(
      contacts: supplier.contacts.where((c) => c.id != contactId).toList(),
    );
    ref.read(mockSuppliersProvider.notifier).update(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suppliers = ref.watch(mockSuppliersProvider);
    MockSupplier? supplier;
    for (final s in suppliers) {
      if (s.id == widget.supplierId) {
        supplier = s;
        break;
      }
    }

    if (supplier == null) {
      return const SizedBox.shrink();
    }

    final s = supplier;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;

    final scrollContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Title row ────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isDark
                  ? AppColors.primaryBlue.withValues(alpha: 0.35)
                  : AppColors.lightBlue,
              child: Text(
                s.name.isNotEmpty ? s.name.substring(0, 1).toUpperCase() : '?',
                style: AppTextStyles.h2(
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: AppTextStyles.h2(color: textPrimary),
                  ),
                  if (s.categories.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacing8),
                    Text(
                      'Catégories de produits',
                      style: AppTextStyles.caption(color: textSecondary),
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    Wrap(
                      spacing: AppConstants.spacing8,
                      runSpacing: AppConstants.spacing8,
                      children: s.categories.map((cat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primaryBlue.withValues(alpha: 0.2)
                                : AppColors.lightBlue.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.skyBlue.withValues(alpha: 0.3)
                                  : AppColors.primaryBlue
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            cat,
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ).copyWith(fontWeight: FontWeight.w500),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onClose != null)
              AppCloseButton(onPressed: widget.onClose),
          ],
        ),
        const SizedBox(height: AppConstants.spacing20),
        // ── Info fields ──────────────────────────────────────────────
        _InfoSection(
          title: 'Coordonnées',
          isDark: isDark,
          children: [
            if (s.phone.isNotEmpty)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: s.phone,
                isDark: isDark,
              ),
            if (s.email.isNotEmpty)
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'E-mail',
                value: s.email,
                isDark: isDark,
              ),
            if (s.location.isNotEmpty)
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Lieu',
                value: s.location,
                isDark: isDark,
              ),
            if (s.phone.isEmpty && s.email.isEmpty && s.location.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppConstants.spacing8),
                child: Text(
                  'Aucune coordonnée ajoutée.',
                  style: AppTextStyles.caption(color: textSecondary),
                ),
              ),
          ],
        ),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spacing16),
          _InfoSection(
            title: 'Note',
            isDark: isDark,
            children: [
              Text(
                s.note,
                style: AppTextStyles.body(color: textPrimary),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppConstants.spacing16),
        // ── Contacts ────────────────────────────────────────────────
        _InfoSection(
          title: 'Contacts',
          trailing: TextButton.icon(
            onPressed: () => _openAddContact(context, s),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ajouter'),
            style: TextButton.styleFrom(
              foregroundColor:
                  isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
          isDark: isDark,
          children: s.contacts.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppConstants.spacing8),
                    child: Text(
                      'Aucun contact pour le moment.',
                      style: AppTextStyles.caption(color: textSecondary),
                    ),
                  ),
                ]
              : s.contacts
                  .asMap()
                  .entries
                  .map(
                    (e) => _ContactRow(
                      contact: e.value,
                      isDark: isDark,
                      showDivider: e.key < s.contacts.length - 1,
                      onEdit: () => _openEditContact(context, s, e.value),
                      onDelete: () => _deleteContact(ref, s, e.value.id),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: AppConstants.spacing16),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: scrollContent,
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.6)
              : AppColors.darkGray.withValues(alpha: 0.2),
        ),
        _PanelActionBar(
          isDark: isDark,
          onEdit: () => _openEditSupplier(context, s),
          bottomInset: MediaQuery.viewInsetsOf(context).bottom,
        ),
      ],
    );

    if (widget.embedded) return body;

    final h = MediaQuery.sizeOf(context).height;
    return SizedBox(height: h, child: body);
  }
}

// ─── Panel sub-widgets ────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.isDark,
    required this.children,
    this.trailing,
  });

  final String title;
  final bool isDark;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.h3(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: AppConstants.spacing8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
            vertical: AppConstants.spacing12,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkBackground.withValues(alpha: 0.4)
                : AppColors.lightBlue.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder
                  : AppColors.darkGray.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.toUpperCase(),
                style: AppTextStyles.caption(color: labelColor).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
          const SizedBox(width: AppConstants.spacing8),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.isDark,
    required this.showDivider,
    required this.onEdit,
    required this.onDelete,
  });

  final MockSupplierContact contact;
  final bool isDark;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isDark
                    ? AppColors.primaryBlue.withValues(alpha: 0.25)
                    : AppColors.lightBlue,
                child: Text(
                  contact.name.isNotEmpty
                      ? contact.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppConstants.spacing8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: AppTextStyles.body(color: textPrimary)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (contact.title.isNotEmpty)
                      Text(
                        contact.title,
                        style: AppTextStyles.caption(color: textSecondary),
                      ),
                    if (contact.phone.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: AppConstants.spacing4),
                        child: Row(
                          children: [
                            Icon(Icons.phone_outlined,
                                size: 12, color: textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              contact.phone,
                              style:
                                  AppTextStyles.caption(color: textSecondary),
                            ),
                          ],
                        ),
                      ),
                    if (contact.email.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: AppConstants.spacing4),
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined,
                                size: 12, color: textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                contact.email,
                                style:
                                    AppTextStyles.caption(color: textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier le contact',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: textSecondary,
                ),
              ),
              IconButton(
                tooltip: 'Retirer le contact',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: AppColors.boldRed,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: isDark
                ? AppColors.darkBorder
                : AppColors.darkGray.withValues(alpha: 0.2),
          ),
      ],
    );
  }
}

class _PanelActionBar extends StatelessWidget {
  const _PanelActionBar({
    required this.isDark,
    required this.onEdit,
    required this.bottomInset,
  });

  final bool isDark;
  final VoidCallback onEdit;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    return Material(
      color: bg,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spacing16,
          AppConstants.spacing8,
          AppConstants.spacing16,
          AppConstants.spacing8 + bottomInset,
        ),
        child: AppButton(
          label: 'Modifier le fournisseur',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onEdit,
          fullWidth: true,
          compact: true,
        ),
      ),
    );
  }
}

// ─── Add / Edit supplier (shared: bottom sheet + right panel + mobile full screen)

/// Bottom sheet wrapper for editing an existing supplier (from detail panel).
class _AddEditSupplierSheet extends ConsumerWidget {
  const _AddEditSupplierSheet({required this.existing});

  final MockSupplier existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AddEditSupplierForm(
      existing: existing,
      embedded: false,
      onCancel: () => Navigator.pop(context),
      onSuccess: () => Navigator.pop(context),
    );
  }
}

class _AddEditSupplierForm extends ConsumerStatefulWidget {
  const _AddEditSupplierForm({
    required this.existing,
    required this.embedded,
    required this.onCancel,
    required this.onSuccess,
  });

  final MockSupplier? existing;
  final bool embedded;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;

  @override
  ConsumerState<_AddEditSupplierForm> createState() =>
      _AddEditSupplierFormState();
}

class _AddEditSupplierFormState extends ConsumerState<_AddEditSupplierForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _noteCtrl;
  late List<String> _categories;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _categories = List<String>.from(e?.categories ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final notifier = ref.read(mockSuppliersProvider.notifier);
    final e = widget.existing;
    if (e == null) {
      notifier.add(MockSupplier(
        id: 0,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        categories: List.from(_categories),
      ));
    } else {
      notifier.update(e.copyWith(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        categories: List.from(_categories),
      ));
    }
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.existing != null;
    final fill = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final borderDecoration = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;

    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: fill,
          border: borderDecoration,
        );

    final scrollableFields = <Widget>[
      if (!widget.embedded) ...[
        Text(
          isEdit ? 'Modifier le fournisseur' : 'Nouveau fournisseur',
          style: AppTextStyles.h2(color: textPrimary),
        ),
        const SizedBox(height: AppConstants.spacing20),
      ],
      TextField(
        controller: _nameCtrl,
        decoration: dec('Nom de l\'entreprise'),
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: AppConstants.spacing12),
      PhoneField(
        controller: _phoneCtrl,
        label: 'Téléphone',
      ),
      const SizedBox(height: AppConstants.spacing12),
      TextField(
        controller: _emailCtrl,
        decoration: dec('E-mail'),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: AppConstants.spacing12),
      TextField(
        controller: _locationCtrl,
        decoration: dec('Lieu / adresse'),
      ),
      const SizedBox(height: AppConstants.spacing12),
      TextField(
        controller: _noteCtrl,
        decoration: dec('Note (facultatif)'),
        maxLines: 3,
      ),
      const SizedBox(height: AppConstants.spacing16),
      SupplierCategoryField(
        categories: _categories,
        onCategoriesChanged: (next) => setState(() => _categories = next),
      ),
      const SizedBox(height: AppConstants.spacing24),
    ];

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dividerColor = isDark
        ? AppColors.darkBorder
        : AppColors.darkGray.withValues(alpha: 0.22);

    Widget actionRow() {
      final h = AppConstants.buttonHeightCompact;
      final cancelStyle = OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size(0, h),
        maximumSize: Size(double.infinity, h),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: h,
              child: AppButton(
                label: isEdit ? 'Enregistrer' : 'Ajouter un fournisseur',
                icon: isEdit ? Icons.save_outlined : Icons.add,
                onPressed: _save,
                fullWidth: true,
                compact: true,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacing12),
          Expanded(
            child: SizedBox(
              height: h,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: cancelStyle,
                child: const Text('Annuler'),
              ),
            ),
          ),
        ],
      );
    }

    return widget.embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacing24,
                  AppConstants.spacing16,
                  AppConstants.spacing8,
                  AppConstants.spacing8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Modifier le fournisseur' : 'Nouveau fournisseur',
                        style: AppTextStyles.h2(color: textPrimary),
                      ),
                    ),
                    AppCloseButton(onPressed: widget.onCancel),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacing24,
                    0,
                    AppConstants.spacing24,
                    AppConstants.spacing8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: scrollableFields,
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: dividerColor),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppConstants.spacing24,
                  AppConstants.spacing8,
                  AppConstants.spacing24,
                  AppConstants.spacing8 + bottomInset,
                ),
                child: actionRow(),
              ),
            ],
          )
        : Padding(
            padding: EdgeInsets.only(
              left: AppConstants.spacing24,
              right: AppConstants.spacing24,
              top: AppConstants.spacing24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: scrollableFields,
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: dividerColor),
                Padding(
                  padding: EdgeInsets.only(
                    top: AppConstants.spacing8,
                    bottom: bottomInset + AppConstants.spacing16,
                  ),
                  child: actionRow(),
                ),
              ],
            ),
          );
  }
}

// ─── Add / Edit contact sheet ─────────────────────────────────────────────────

class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.supplier, this.existing});

  final MockSupplier supplier;
  final MockSupplierContact? existing;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final e = widget.existing;
    final contact = MockSupplierContact(
      id: e?.id ?? 'c_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      title: _titleCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );
    final updatedContacts = e == null
        ? [...widget.supplier.contacts, contact]
        : [
            for (final c in widget.supplier.contacts)
              c.id == contact.id ? contact : c,
          ];
    ref.read(mockSuppliersProvider.notifier).update(
          widget.supplier.copyWith(contacts: updatedContacts),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.existing != null;
    final fill = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final borderDecoration = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );

    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: fill,
          border: borderDecoration,
        );

    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        top: AppConstants.spacing24,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? 'Modifier le contact' : 'Ajouter un contact',
            style: AppTextStyles.h2(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ),
          ),
          const SizedBox(height: AppConstants.spacing4),
          Text(
            widget.supplier.name,
            style: AppTextStyles.caption(),
          ),
          const SizedBox(height: AppConstants.spacing20),
          TextField(
            controller: _nameCtrl,
            decoration: dec('Nom complet'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppConstants.spacing12),
          TextField(
            controller: _titleCtrl,
            decoration: dec('Titre / rôle (facultatif)'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppConstants.spacing12),
          PhoneField(
            controller: _phoneCtrl,
            label: 'Téléphone',
          ),
          const SizedBox(height: AppConstants.spacing12),
          TextField(
            controller: _emailCtrl,
            decoration: dec('E-mail (facultatif)'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppConstants.spacing24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppConstants.buttonHeight / 2),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: isEdit ? 'Enregistrer le contact' : 'Ajouter un contact',
                  icon:
                      isEdit ? Icons.save_outlined : Icons.person_add_outlined,
                  onPressed: _save,
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

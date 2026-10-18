import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/customer.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/list_page_nav.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

enum _CustomerFilter { all, withBalance, settled, blocked, inactive }

class CustomerListScreen extends ConsumerStatefulWidget {
  final String backRoute;
  final String detailRoute;
  final String formRoute;
  final String collectionsRoute;
  /// When true, customer detail shows an extra "Hôtel" section with stays/balance.
  final bool showHotelSection;
  /// When false, the title row and actions (Collections, New) are hidden (for use inside tabbed layout).
  final bool showHeader;
  /// Override which provider supplies the data. Defaults to [customerProvider].
  final StateNotifierProvider<CustomerNotifier, CustomerState>? dataProvider;

  const CustomerListScreen({
    super.key,
    required this.backRoute,
    required this.detailRoute,
    required this.formRoute,
    required this.collectionsRoute,
    this.showHotelSection = false,
    this.showHeader = true,
    this.dataProvider,
  });

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  static const int _pageSize = 10;
  static const double _drawerWidth = 480.0;
  static const double _mobileBreakpoint = 600.0;

  String _search = '';
  _CustomerFilter _filter = _CustomerFilter.all;
  int _currentPage = 1;
  final Map<_CustomerFilter, List<Customer>> _filterCache = {};
  Customer? _selectedCustomer;
  bool _drawerOpen = false;

  void _openDrawer(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _drawerOpen = true;
    });
  }

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
    Future.delayed(AppConstants.animNormal, () {
      if (mounted) setState(() => _selectedCustomer = null);
    });
  }

  List<Customer> _getFilteredCustomers(CustomerState state) {
    List<Customer> byFilter;
    if (_filterCache.containsKey(_filter)) {
      byFilter = _filterCache[_filter]!;
    } else {
      byFilter = state.customers.where((c) {
        final balance = state.balanceFor(c.id);
        return switch (_filter) {
          _CustomerFilter.all => true,
          _CustomerFilter.withBalance => balance > 0,
          _CustomerFilter.settled => balance == 0,
          _CustomerFilter.blocked => c.isCreditBlocked,
          _CustomerFilter.inactive => !c.isActive,
        };
      }).toList();
      _filterCache[_filter] = byFilter;
    }
    if (_search.isEmpty) return byFilter;
    return byFilter.where((c) {
      return c.name.toLowerCase().contains(_search.toLowerCase()) ||
          c.phone.contains(_search);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.dataProvider ?? customerProvider;
    final state = ref.watch(provider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(provider, (prev, next) {
      if (prev != next && mounted) {
        setState(() {
          _filterCache.clear();
          _currentPage = 1;
        });
      }
    });

    final filtered = _getFilteredCustomers(state);
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 31);
    final page = _currentPage.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final paginated = filtered.skip(start).take(_pageSize).toList();

    final totalOwed = state.totalOutstandingHtg;

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < _mobileBreakpoint;
      final panelW = isMobile
          ? constraints.maxWidth
          : _drawerWidth.clamp(0.0, constraints.maxWidth);
      final listBody = _buildListBody(
        context,
        state,
        isDark,
        filtered,
        paginated,
        totalPages,
        page,
        totalOwed,
        isMobile: isMobile,
      );

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            listBody,

            // Scrim
            if (_selectedCustomer != null)
              AnimatedOpacity(
                opacity: _drawerOpen ? 1.0 : 0.0,
                duration: AppConstants.animNormal,
                child: IgnorePointer(
                  ignoring: !_drawerOpen,
                  child: GestureDetector(
                    onTap: _closeDrawer,
                    child: Container(
                        color: Colors.black.withValues(alpha: 0.3)),
                  ),
                ),
              ),

            // Sliding drawer panel
            if (_selectedCustomer != null)
              AnimatedPositioned(
                duration: AppConstants.animNormal,
                curve: Curves.easeOutCubic,
                right: _drawerOpen ? 0 : -panelW,
                top: 0,
                bottom: 0,
                width: panelW,
                child: Material(
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  child: CustomerDetailPanel(
                    key: ValueKey(_selectedCustomer!.id),
                    customer: _selectedCustomer!,
                    isDark: isDark,
                    showHotelSection: widget.showHotelSection,
                    onClose: _closeDrawer,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildListBody(
    BuildContext context,
    CustomerState state,
    bool isDark,
    List<Customer> filtered,
    List<Customer> paginated,
    int totalPages,
    int page,
    double totalOwed, {
    required bool isMobile,
  }) {
    return Padding(
        padding: const EdgeInsets.only(
          left: AppConstants.spacing24,
          right: AppConstants.spacing24,
          top: AppConstants.spacing24,
          bottom: AppConstants.spacing8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Clients',
                            style: AppTextStyles.h1(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.primaryBlue)),
                        if (totalOwed > 0)
                          Text(
                            'Total dû : ${CurrencyFormatter.local(context, totalOwed)}',
                            style:
                                AppTextStyles.caption(color: AppColors.boldRed),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go(widget.collectionsRoute),
                    icon: const Icon(Icons.account_balance_wallet_outlined,
                        size: 16),
                    label: const Text('Recouvrements'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.amber),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context, isDark),
                    icon: const Icon(Icons.person_add_outlined, size: 16),
                    label: const Text('Nouveau'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: AppTextStyles.button(
                        color: AppColors.nearBlack,
                      ).copyWith(fontSize: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusButton),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
            ],

            // Search + filters (responsive: same row on desktop, stacked on small)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= AppConstants.mobileBreakpoint;
                const double chipHeight = 32;
                final searchField = TextField(
                  onChanged: (v) => setState(() {
                    _search = v;
                    _currentPage = 1;
                  }),
                  style: AppTextStyles.body().copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom ou téléphone…',
                    hintStyle: AppTextStyles.caption(),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: chipHeight,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurface : AppColors.white,
                  ),
                );
                final filterChips = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _CustomerFilter.values.map((f) {
                      final label = switch (f) {
                        _CustomerFilter.all => 'Tous',
                        _CustomerFilter.withBalance => 'Avec solde',
                        _CustomerFilter.settled => 'Settled',
                        _CustomerFilter.blocked => 'Bloqué',
                        _CustomerFilter.inactive => 'Inactif',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() {
                            _filter = f;
                            _currentPage = 1;
                          }),
                        ),
                      );
                    }).toList(),
                  ),
                );
                if (isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          filterChips,
                          const SizedBox(width: AppConstants.spacing12),
                          Expanded(
                            child: SizedBox(
                              height: chipHeight,
                              child: searchField,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spacing12),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    searchField,
                    const SizedBox(height: AppConstants.spacing12),
                    filterChips,
                    const SizedBox(height: AppConstants.spacing12),
                  ],
                );
              },
            ),
            const SizedBox(height: AppConstants.spacing8),

            // List
            Expanded(
              child: paginated.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'Aucun client trouvé',
                      message: 'Ajoutez un client ou changez le filtre.',
                    )
                  : ListView.separated(
                      itemCount: paginated.length +
                          (isMobile && totalPages > 1 ? 1 : 0),
                      separatorBuilder: (_, i) {
                        if (isMobile &&
                            totalPages > 1 &&
                            i >= paginated.length - 1) {
                          return const SizedBox(height: AppConstants.spacing16);
                        }
                        return const SizedBox(height: AppConstants.spacing8);
                      },
                      itemBuilder: (context, i) {
                        if (i >= paginated.length) {
                          return Align(
                            alignment: Alignment.centerRight,
                            child: ListPageNav(
                              isDark: isDark,
                              currentPage: page,
                              totalPages: totalPages,
                              onPrevious: page > 1
                                  ? () => setState(() => _currentPage = page - 1)
                                  : null,
                              onNext: page < totalPages
                                  ? () => setState(() => _currentPage = page + 1)
                                  : null,
                            ),
                          );
                        }
                        final c = paginated[i];
                        final balance = state.balanceFor(c.id);
                        return _CustomerCard(
                          customer: c,
                          balance: balance,
                          isDark: isDark,
                          isSelected: _selectedCustomer?.id == c.id,
                          onTap: () => _openDrawer(c),
                        );
                      },
                    ),
            ),

            // Desktop keeps the numbered pager. Mobile uses the list footer.
            if (!isMobile && filtered.isNotEmpty && totalPages > 1) ...[
              const SizedBox(height: AppConstants.spacing4),
              _PaginationBar(
                currentPage: page,
                totalPages: totalPages,
                totalItems: filtered.length,
                pageSize: _pageSize,
                isDark: isDark,
                onPageChanged: (p) => setState(() => _currentPage = p),
              ),
            ],
          ],
        ),
    );
  }


  void _openForm(BuildContext context, bool isDark) {
    showAppBottomSheet(
      context: context,
      child: CustomerFormSheet(isDark: isDark),
    );
  }
}

// ─── Pagination Bar ───────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final bool isDark;
  final ValueChanged<int> onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.isDark,
    required this.onPageChanged,
  });

  Widget _arrowButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color activeColor,
  }) {
    final color = onTap != null ? activeColor : activeColor.withValues(alpha: 0.3);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Center(child: Icon(icon, size: 18, color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = (currentPage - 1) * pageSize + 1;
    final end = (currentPage * pageSize).clamp(0, totalItems);
    final accentColor = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: Text(
              'Showing $start–$end of $totalItems',
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _arrowButton(
                icon: Icons.chevron_left,
                onTap: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                activeColor: accentColor,
              ),
              ..._buildPageNumbers(),
              _arrowButton(
                icon: Icons.chevron_right,
                onTap: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                activeColor: accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers() {
    const int maxVisible = 5;
    if (totalPages <= maxVisible) {
      return List.generate(totalPages, (i) => _pageButton(i + 1));
    }
    final pages = <Widget>[];
    int start = (currentPage - 1).clamp(1, totalPages - maxVisible + 1);
    int end = (start + maxVisible - 1).clamp(1, totalPages);
    if (start > 1) {
      pages.add(_pageButton(1));
      if (start > 2) {
        pages.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('…',
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        ));
      }
    }
    for (int i = start; i <= end; i++) {
      pages.add(_pageButton(i));
    }
    if (end < totalPages) {
      if (end < totalPages - 1) {
        pages.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('…',
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        ));
      }
      pages.add(_pageButton(totalPages));
    }
    return pages;
  }

  Widget _pageButton(int page) {
    final isSelected = page == currentPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isSelected
            ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => onPageChanged(page),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Center(
              child: Text(
                '$page',
                style: AppTextStyles.body(
                  color: isSelected
                      ? AppColors.white
                      : (isDark ? AppColors.warmWhite : AppColors.nearBlack),
                ).copyWith(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Customer Card ────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final double balance;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.customer,
    required this.balance,
    required this.isDark,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: isSelected
          ? (isDark
              ? AppColors.primaryBlue.withValues(alpha: 0.35)
              : AppColors.lightBlue)
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing8,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: customer.isCreditBlocked
                  ? AppColors.boldRed.withValues(alpha: 0.12)
                  : (isDark
                      ? AppColors.primaryBlue.withValues(alpha: 0.25)
                      : AppColors.lightBlue),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: AppTextStyles.body(
                  color: customer.isCreditBlocked
                      ? AppColors.boldRed
                      : (isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (customer.isCreditBlocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.boldRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.boldRed.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'BLOQUÉ',
                          style: AppTextStyles.caption(color: AppColors.boldRed)
                              .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                Text(
                  customer.phone,
                  style: AppTextStyles.caption().copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (balance > 0) ...[
            const SizedBox(width: AppConstants.spacing8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  CurrencyFormatter.local(context, balance),
                  style: AppTextStyles.caption(color: AppColors.boldRed)
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                Text(
                  'doit',
                  style: AppTextStyles.caption().copyWith(fontSize: 10),
                ),
              ],
            ),
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ],
      ),
    );
  }
}

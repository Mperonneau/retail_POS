import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../mock/mock_order_history.dart';
import '../../mock/mock_retail_orders.dart';
import '../../models/order_history.dart';
import '../../models/retail_fulfillment_mode.dart';
import '../../models/retail_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/input_formatters.dart';
import '../../../retail/receipt/sale_receipt_pdf.dart';
import '../../../retail/receipt/sale_receipt_text.dart';
import '../../../retail/widgets/edit_check_sheet.dart';
import '../../../retail/storefront/receipt_scan.dart';
import '../../printing/shop_pdf.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/app_card.dart';
import '../../widgets/list_page_nav.dart';
import '../../widgets/payment_method_block.dart';
import 'order_history_detail.dart';
import '../../widgets/app_close_button.dart';

const int _kPageSize = 10;

/// Which business slice this list shows (restaurant vs retail vs hotel module).
enum OrderHistoryListScope {
  /// Standalone restaurant shell — only dining-room transactions.
  restaurant,

  /// Retail shell — POS / shop transactions only.
  retail,

  /// Hotel shell — user picks Restaurant (integrated dining) vs Hotel (rooms,
  /// room service, minibar, etc.), excluding retail.
  hotelIntegrated,
}

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key, required this.scope});

  final OrderHistoryListScope scope;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';
  int _currentPage = 0;
  OrderHistoryRecord? _selectedRecord;

  /// When [OrderHistoryListScope.hotelIntegrated]: restaurant dining vs hotel
  /// (rooms, room service, minibar — all `module == hotel`).
  OrderHistoryModule _hotelSegment = OrderHistoryModule.hotel;

  final _searchCtrl = TextEditingController();

  /// 0 = Active Orders, 1 = Completed — only used for retail scope.
  int _retailTab = 0;

  /// Selected active order — drives the right-panel overlay at the top level.
  RetailOrder? _selectedActiveOrder;

  List<OrderHistoryRecord> get _filtered {
    return mockOrderHistory.where((r) {
      switch (widget.scope) {
        case OrderHistoryListScope.restaurant:
          if (r.module != OrderHistoryModule.restaurant) return false;
          break;
        case OrderHistoryListScope.retail:
          if (r.module != OrderHistoryModule.retail) return false;
          break;
        case OrderHistoryListScope.hotelIntegrated:
          if (r.module != OrderHistoryModule.restaurant &&
              r.module != OrderHistoryModule.hotel) {
            return false;
          }
          if (r.module != _hotelSegment) return false;
          break;
      }
      if (_startDate != null &&
          r.paidAt.isBefore(
              DateTime(_startDate!.year, _startDate!.month, _startDate!.day))) {
        return false;
      }
      if (_endDate != null &&
          r.paidAt.isAfter(DateTime(
              _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchReceipt = r.receiptNumber.toLowerCase().contains(q);
        final matchName =
            r.receiptName != null && r.receiptName!.toLowerCase().contains(q);
        if (!matchReceipt && !matchName) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  }

  List<OrderHistoryRecord> get _paginated {
    final f = _filtered;
    final start = _currentPage * _kPageSize;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _kPageSize).clamp(0, f.length));
  }

  int get _totalPages => ((_filtered.length - 1) ~/ _kPageSize) + 1;

  /// Active retail orders after applying shared search + date filters.
  List<RetailOrder> get _filteredActiveOrders {
    final all = ref.watch(retailOrdersProvider);
    return all.where((o) {
      if (o.status.isTerminal) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!o.orderNumber.toLowerCase().contains(q) &&
            !(o.clientName?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      if (_startDate != null &&
          o.paidAt.isBefore(DateTime(
              _startDate!.year, _startDate!.month, _startDate!.day))) {
        return false;
      }
      if (_endDate != null &&
          o.paidAt.isAfter(DateTime(
              _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  }

  @override
  void initState() {
    super.initState();
    if (widget.scope == OrderHistoryListScope.retail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingReceipt());
    }
  }

  void _openPendingReceipt() {
    if (!mounted) return;
    final id = ref.read(pendingReceiptScanProvider);
    if (id == null || id.isEmpty) return;
    final order = ref
        .read(retailOrdersProvider)
        .where((row) => row.id == 'vit_$id')
        .firstOrNull;
    if (order == null) return;
    ref.read(pendingReceiptScanProvider.notifier).state = null;
    final mobile =
        MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;
    setState(() {
      _retailTab = 0;
      _selectedActiveOrder = mobile ? null : order;
    });
    if (mobile) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _RetailOrderDetailPage(order: order)),
      );
    }
  }

  void _resetPage() => setState(() => _currentPage = 0);

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _currentPage = 0;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile =
        MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;

    if (widget.scope == OrderHistoryListScope.retail) {
      return _buildRetailTabbed(context, isDark, isMobile);
    }
    return _buildStandardLayout(context, isDark, isMobile);
  }

  Widget _buildRetailTabbed(
      BuildContext context, bool isDark, bool isMobile) {
    final activeOrders = _filteredActiveOrders;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Main content (title + filters + toggle + tabs) ────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacing24,
                  AppConstants.spacing24,
                  AppConstants.spacing24,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Historique',
                              style: AppTextStyles.h1(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.primaryBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_retailTab == 1 && _totalPages > 1)
                            Flexible(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: _buildPagination(isDark),
                              ),
                            ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Historique',
                            style: AppTextStyles.h1(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: AppConstants.spacing16),
                    if (!isMobile)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildRetailToggle(isDark, dense: true),
                          const SizedBox(width: AppConstants.spacing12),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _buildSharedFilters(
                                context,
                                isDark,
                                dense: true,
                                retailToolbarEnd: true,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSharedFilters(
                            context,
                            isDark,
                            dense: true,
                            retailToolbarEnd: false,
                          ),
                          const SizedBox(height: AppConstants.spacing12),
                          _buildRetailToggle(isDark, dense: true),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _retailTab,
                  children: [
                    _RetailActiveOrdersTab(
                      orders: activeOrders,
                      isDark: isDark,
                      isMobile: isMobile,
                      onOrderSelected: (order) =>
                          setState(() => _selectedActiveOrder = order),
                    ),
                    _buildStandardLayout(
                      context,
                      isDark,
                      isMobile,
                      showFilterRow: false,
                      hoistDetailDrawer: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Completed-order drawer: full page height (retail tab only) ─────
          if (_retailTab == 1 &&
              _selectedRecord != null &&
              !isMobile)
            Positioned.fill(
              child: _DesktopDetailDrawer(
                record: _selectedRecord!,
                isDark: isDark,
                onClose: () => setState(() => _selectedRecord = null),
              ),
            ),

          // ── Full-height drawer overlay (non-mobile) ───────────────────────
          if (_selectedActiveOrder != null && !isMobile)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Scrim — tap to close
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedActiveOrder = null),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.20),
                      ),
                    ),
                  ),
                  // Detail panel
                  Container(
                    width: AppConstants.retailDetailSidePanelWidth(
                        MediaQuery.sizeOf(context).width),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 28,
                          offset: const Offset(-4, 0),
                        ),
                      ],
                    ),
                    child: _RetailOrderDetailPanel(
                      order: _selectedActiveOrder!,
                      isDark: isDark,
                      onClose: () =>
                          setState(() => _selectedActiveOrder = null),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Pill-shaped segmented toggle between Active Orders and Completed.
  Widget _buildRetailToggle(bool isDark, {bool dense = false}) {
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD);
    final radius = dense ? 18.0 : 24.0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        color: isDark ? AppColors.darkSurface : AppColors.white,
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleTab(
              icon: Icons.pending_actions_outlined,
              label: 'Commandes en cours',
              badge: _ActiveCountBadge(isDark: isDark),
              isSelected: _retailTab == 0,
              isDark: isDark,
              isLeft: true,
              dense: dense,
              onTap: () {
                if (_retailTab == 0) return;
                setState(() {
                  _retailTab = 0;
                  _resetPage();
                });
              },
            ),
            Container(width: 1, color: borderColor),
            _ToggleTab(
              icon: Icons.check_circle_outline_rounded,
              label: 'Terminé',
              isSelected: _retailTab == 1,
              isDark: isDark,
              isLeft: false,
              dense: dense,
              onTap: () {
                if (_retailTab == 1) return;
                setState(() {
                  _retailTab = 1;
                  _resetPage();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Shared filter row for the retail tabbed view (dates + search; count is below).
  Widget _buildSharedFilters(
    BuildContext context,
    bool isDark, {
    bool retailToolbarEnd = false,
    bool dense = false,
  }) {
    final fromChip = _DateChip(
      label: _startDate == null ? 'De' : _formatDate(_startDate!),
      icon: Icons.calendar_today_outlined,
      active: _startDate != null,
      isDark: isDark,
      dense: dense,
      onTap: () => _pickDate(context, true),
      onClear: _startDate != null
          ? () => setState(() {
                _startDate = null;
                _resetPage();
              })
          : null,
    );
    final toChip = _DateChip(
      label: _endDate == null ? 'À' : _formatDate(_endDate!),
      icon: Icons.event_outlined,
      active: _endDate != null,
      isDark: isDark,
      dense: dense,
      onTap: () => _pickDate(context, false),
      onClear: _endDate != null
          ? () => setState(() {
                _endDate = null;
                _resetPage();
              })
          : null,
    );
    final pillSearch = _PillSearch(
      controller: _searchCtrl,
      hintText: 'Commande n° ou client…',
      isDark: isDark,
      dense: dense,
      width: dense ? 188 : 210,
      hasValue: _searchQuery.isNotEmpty,
      onChanged: (v) => setState(() {
        _searchQuery = v.trim();
        _resetPage();
      }),
      onClear: () {
        _searchCtrl.clear();
        setState(() {
          _searchQuery = '';
          _resetPage();
        });
      },
    );

    if (retailToolbarEnd) {
      return Wrap(
        spacing: dense ? 6 : 8,
        runSpacing: dense ? 6 : 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [fromChip, toChip, pillSearch],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PillSearch(
            controller: _searchCtrl,
            hintText: 'Commande n° ou client…',
            isDark: isDark,
            dense: dense,
            expand: true,
            hasValue: _searchQuery.isNotEmpty,
            onChanged: (v) => setState(() {
              _searchQuery = v.trim();
              _resetPage();
            }),
            onClear: () {
              _searchCtrl.clear();
              setState(() {
                _searchQuery = '';
                _resetPage();
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        fromChip,
        const SizedBox(width: 6),
        toChip,
      ],
    );
  }

  Widget _buildStandardLayout(
      BuildContext context, bool isDark, bool isMobile,
      {bool showFilterRow = true, bool hoistDetailDrawer = false}) {
    final showHeader = widget.scope != OrderHistoryListScope.retail;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppConstants.spacing24,
              showHeader ? AppConstants.spacing24 : AppConstants.spacing8,
              AppConstants.spacing24,
              AppConstants.spacing24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  if (!isMobile)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            'Historique',
                            style: AppTextStyles.h1(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.primaryBlue,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_totalPages > 1)
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: _buildPagination(isDark),
                            ),
                          ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Historique',
                          style: AppTextStyles.h1(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppConstants.spacing16),
                ],
                if (showFilterRow) ...[
                  _buildFilters(context, isDark, isMobile),
                  const SizedBox(height: AppConstants.spacing16),
                ],
                Expanded(child: _buildTable(context, isDark, isMobile)),
              ],
            ),
          ),
          // Desktop drawer — inline only when not hoisted to retail tab root
          if (_selectedRecord != null && !isMobile && !hoistDetailDrawer)
            Positioned.fill(
              child: _DesktopDetailDrawer(
                record: _selectedRecord!,
                isDark: isDark,
                onClose: () => setState(() => _selectedRecord = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, bool isDark, bool isMobile) {
    final fromChip = _DateChip(
      label: _startDate == null ? 'De' : _formatDate(_startDate!),
      icon: Icons.calendar_today_outlined,
      active: _startDate != null,
      isDark: isDark,
      onTap: () => _pickDate(context, true),
      onClear: _startDate != null
          ? () => setState(() { _startDate = null; _resetPage(); })
          : null,
    );
    final toChip = _DateChip(
      label: _endDate == null ? 'À' : _formatDate(_endDate!),
      icon: Icons.event_outlined,
      active: _endDate != null,
      isDark: isDark,
      onTap: () => _pickDate(context, false),
      onClear: _endDate != null
          ? () => setState(() { _endDate = null; _resetPage(); })
          : null,
    );
    final countText = Text(
      '${_filtered.length} result${_filtered.length == 1 ? '' : 's'}',
      style: AppTextStyles.caption(
          color: isDark ? AppColors.coolGray : AppColors.darkGray),
    );
    final pillSearch = _PillSearch(
      controller: _searchCtrl,
      hintText: 'Reçu n° ou nom…',
      isDark: isDark,
      hasValue: _searchQuery.isNotEmpty,
      onChanged: (v) => setState(() { _searchQuery = v.trim(); _resetPage(); }),
      onClear: () {
        _searchCtrl.clear();
        setState(() { _searchQuery = ''; _resetPage(); });
      },
    );

    if (!isMobile) {
      return Row(
        children: [
          if (widget.scope == OrderHistoryListScope.hotelIntegrated) ...[
            SegmentedButton<OrderHistoryModule>(
              segments: const [
                ButtonSegment<OrderHistoryModule>(
                  value: OrderHistoryModule.restaurant,
                  label: Text('Restaurant'),
                  icon: Icon(Icons.restaurant_outlined, size: 18),
                ),
                ButtonSegment<OrderHistoryModule>(
                  value: OrderHistoryModule.hotel,
                  label: Text('Hôtel'),
                  icon: Icon(Icons.hotel_outlined, size: 18),
                ),
              ],
              selected: {_hotelSegment},
              onSelectionChanged: (Set<OrderHistoryModule> next) {
                setState(() { _hotelSegment = next.first; _resetPage(); });
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          fromChip,
          const SizedBox(width: 6),
          toChip,
          const SizedBox(width: 10),
          countText,
          const Spacer(),
          pillSearch,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.scope == OrderHistoryListScope.hotelIntegrated) ...[
          SegmentedButton<OrderHistoryModule>(
            segments: const [
              ButtonSegment<OrderHistoryModule>(
                value: OrderHistoryModule.restaurant,
                label: Text('Restaurant'),
                icon: Icon(Icons.restaurant_outlined, size: 18),
              ),
              ButtonSegment<OrderHistoryModule>(
                value: OrderHistoryModule.hotel,
                label: Text('Hôtel'),
                icon: Icon(Icons.hotel_outlined, size: 18),
              ),
            ],
            selected: {_hotelSegment},
            onSelectionChanged: (Set<OrderHistoryModule> next) {
              setState(() { _hotelSegment = next.first; _resetPage(); });
            },
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: _PillSearch(
                controller: _searchCtrl,
                hintText: 'Reçu n° ou nom…',
                isDark: isDark,
                expand: true,
                hasValue: _searchQuery.isNotEmpty,
                onChanged: (v) => setState(() {
                  _searchQuery = v.trim();
                  _resetPage();
                }),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() {
                    _searchQuery = '';
                    _resetPage();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            fromChip,
            const SizedBox(width: 6),
            toChip,
          ],
        ),
      ],
    );
  }

  Widget _buildTable(
      BuildContext context, bool isDark, bool isMobile) {
    final records = _paginated;
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: isDark ? AppColors.coolGray : AppColors.darkGray),
            const SizedBox(height: AppConstants.spacing16),
            Text('Aucune transaction trouvée',
                style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)),
          ],
        ),
      );
    }

    if (isMobile) {
      return ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBackground.withValues(alpha: 0.5)
                        : AppColors.lightBlue.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppConstants.radiusCard),
                      topRight: Radius.circular(AppConstants.radiusCard),
                    ),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        'Reçu / nom',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                    ),
                    Text(
                      'Total',
                      style: AppTextStyles.caption(
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                for (var i = 0; i < records.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _HistoryRowTile(
                    record: records[i],
                    isDark: isDark,
                    isMobile: true,
                    isSelected: _selectedRecord?.receiptNumber ==
                        records[i].receiptNumber,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderHistoryDetailPage(record: records[i]),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          if (_totalPages > 1) ...[
            const SizedBox(height: AppConstants.spacing16),
            Align(
              alignment: Alignment.centerRight,
              child: ListPageNav(
                isDark: isDark,
                currentPage: _currentPage + 1,
                totalPages: _totalPages,
                onPrevious: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
                onNext: _currentPage < _totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            ),
          ],
        ],
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkBackground.withValues(alpha: 0.5)
                  : AppColors.lightBlue.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppConstants.radiusCard),
                topRight: Radius.circular(AppConstants.radiusCard),
              ),
            ),
            child: isMobile
                ? Row(children: [
                    Expanded(child: Text('Reçu / nom',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    Text('Total',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray)),
                  ])
                : Row(children: [
                    SizedBox(width: 140, child: Text('Reçu n°',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    SizedBox(width: 140, child: Text('Date et heure',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    Expanded(child: Text('Nom / source',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    SizedBox(width: 110, child: Text('Paiement',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    SizedBox(width: 120, child: Text('Total',
                        textAlign: TextAlign.end,
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray))),
                    const SizedBox(width: 28),
                  ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (ctx, i) {
                final r = records[i];
                final isSelected = _selectedRecord?.receiptNumber == r.receiptNumber;
                return Material(
                  color: isSelected
                      ? (isDark
                          ? AppColors.sidebarSelected.withValues(alpha: 0.4)
                          : AppColors.lightBlue)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (isMobile) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderHistoryDetailPage(
                              record: r,
                            ),
                          ),
                        );
                      } else {
                        setState(() => _selectedRecord =
                            isSelected ? null : r);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacing16, vertical: 12),
                      child: isMobile
                          ? _MobileRow(record: r, isDark: isDark)
                          : _DesktopRow(record: r, isDark: isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(bool isDark) {
    if (_totalPages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _currentPage > 0
              ? () => setState(() => _currentPage--)
              : null,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Précédent',
        ),
        ...List.generate(_totalPages, (i) {
          final isActive = i == _currentPage;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => setState(() => _currentPage = i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primaryBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${i + 1}',
                  style: AppTextStyles.caption(
                      color: isActive
                          ? AppColors.white
                          : (isDark ? AppColors.coolGray : AppColors.darkGray)),
                ),
              ),
            ),
          );
        }),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _currentPage < _totalPages - 1
              ? () => setState(() => _currentPage++)
              : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Suivant',
        ),
      ],
    );
  }
}

// ── Row widgets ──────────────────────────────────────────────────────────────

class _HistoryRowTile extends StatelessWidget {
  const _HistoryRowTile({
    required this.record,
    required this.isDark,
    required this.isMobile,
    required this.isSelected,
    required this.onTap,
  });

  final OrderHistoryRecord record;
  final bool isDark;
  final bool isMobile;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? (isDark
              ? AppColors.sidebarSelected.withValues(alpha: 0.4)
              : AppColors.lightBlue)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
            vertical: 12,
          ),
          child: isMobile
              ? _MobileRow(record: record, isDark: isDark)
              : _DesktopRow(record: record, isDark: isDark),
        ),
      ),
    );
  }
}

class _DesktopRow extends StatelessWidget {
  final OrderHistoryRecord record;
  final bool isDark;

  const _DesktopRow({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(record.receiptNumber,
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)),
        ),
        SizedBox(
          width: 140,
          child: Text(_formatDate(record.paidAt, withTime: true),
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.receiptName != null)
                Text(record.receiptName!,
                    style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
                    overflow: TextOverflow.ellipsis),
              Text(record.source,
                  style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        SizedBox(
          width: 110,
          child: _PaymentBadges(record: record),
        ),
        SizedBox(
          width: 120,
          child: Text(CurrencyFormatter.local(context, record.total),
              textAlign: TextAlign.end,
              style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right,
            size: 18,
            color: isDark ? AppColors.coolGray : AppColors.darkGray),
      ],
    );
  }
}

class _MobileRow extends StatelessWidget {
  final OrderHistoryRecord record;
  final bool isDark;

  const _MobileRow({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record.receiptNumber,
                  style: AppTextStyles.caption(
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)),
              const SizedBox(height: 2),
              if (record.receiptName != null)
                Text(record.receiptName!,
                    style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
                    overflow: TextOverflow.ellipsis),
              Text(record.source,
                  style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray)),
              const SizedBox(height: 4),
              Row(children: [
                _PaymentBadges(record: record),
                const SizedBox(width: 6),
                Text(_formatDate(record.paidAt),
                    style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray)),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(CurrencyFormatter.local(context, record.total),
            style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right,
            size: 16,
            color: isDark ? AppColors.coolGray : AppColors.darkGray),
      ],
    );
  }
}

// ── Desktop right drawer overlay ─────────────────────────────────────────────

class _DesktopDetailDrawer extends StatelessWidget {
  final OrderHistoryRecord record;
  final bool isDark;
  final VoidCallback onClose;

  const _DesktopDetailDrawer({
    required this.record,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.18)),
          ),
        ),
        Container(
          width: AppConstants.retailDetailSidePanelWidth(
              MediaQuery.sizeOf(context).width),
          color: isDark ? AppColors.darkSurface : AppColors.white,
          child: OrderHistoryDetailContent(
            record: record,
            isDark: isDark,
            onClose: onClose,
          ),
        ),
      ],
    );
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

class _PaymentBadge extends StatelessWidget {
  final PaymentMethodType method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (method) {
      PaymentMethodType.moncash => ('MonCash', AppColors.amber),
      PaymentMethodType.card => ('Carte', AppColors.primaryBlue),
      PaymentMethodType.cash => ('Espèces', AppColors.deepGreen),
      PaymentMethodType.credit => ('Crédit', AppColors.boldRed),
      PaymentMethodType.paymentLink => ('Lien', const Color(0xFF7C3AED)),
      PaymentMethodType.check => ('Chèque', const Color(0xFF0F766E)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: AppTextStyles.caption(color: color)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// Multiple payment badges in a wrap (for multi-method orders).
class _PaymentBadges extends StatelessWidget {
  final OrderHistoryRecord record;
  const _PaymentBadges({required this.record});

  @override
  Widget build(BuildContext context) {
    final methods = record.allPaymentMethods;
    if (methods.length == 1) return _PaymentBadge(method: methods.first);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: methods.map((m) => _PaymentBadge(method: m)).toList(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool isDark;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.isDark,
    this.dense = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 5 : 8,
        ),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primaryBlue.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(
            color: active
                ? AppColors.primaryBlue
                : (isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD)),
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: dense ? 13 : 15,
              color: active
                  ? AppColors.primaryBlue
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            SizedBox(width: dense ? 5 : 6),
            Text(
              label,
              style: AppTextStyles.caption(
                color: active
                    ? AppColors.primaryBlue
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: dense ? 12 : 13,
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Active orders count badge ─────────────────────────────────────────────────

class _ActiveCountBadge extends ConsumerWidget {
  final bool isDark;

  const _ActiveCountBadge({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(retailOrdersProvider
        .select((orders) => orders.where((o) => !o.status.isTerminal).length));
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amber,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.caption(color: AppColors.nearBlack)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Pill toggle tab option ────────────────────────────────────────────────────

class _ToggleTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? badge;
  final bool isSelected;
  final bool isDark;
  final bool isLeft;
  final bool dense;
  final VoidCallback onTap;

  const _ToggleTab({
    required this.icon,
    required this.label,
    this.badge,
    required this.isSelected,
    required this.isDark,
    required this.isLeft,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = dense ? 17.0 : 23.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 18,
          vertical: dense ? 5 : 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: isLeft
              ? BorderRadius.horizontal(left: Radius.circular(r))
              : BorderRadius.horizontal(right: Radius.circular(r)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: dense ? 14 : 15,
              color: isSelected
                  ? AppColors.white
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            SizedBox(width: dense ? 5 : 6),
            Text(
              label,
              style: dense
                  ? AppTextStyles.caption(
                      color: isSelected
                          ? AppColors.white
                          : (isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray),
                    ).copyWith(fontWeight: FontWeight.w600)
                  : AppTextStyles.button(
                      color: isSelected
                          ? AppColors.white
                          : (isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray),
                    ),
            ),
            if (badge != null) ...[
              SizedBox(width: dense ? 4 : 6),
              badge!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Pill search field ─────────────────────────────────────────────────────────

class _PillSearch extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isDark;
  final bool dense;
  final double width;
  final bool expand;
  final bool hasValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _PillSearch({
    required this.controller,
    required this.hintText,
    required this.isDark,
    this.dense = false,
    this.width = 210,
    this.expand = false,
    required this.hasValue,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final br = dense ? 20.0 : 24.0;
    final field = TextField(
        controller: controller,
        onChanged: onChanged,
        style: dense
            ? AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(fontSize: 13)
            : null,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: dense
              ? AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                )
              : null,
          prefixIcon: Icon(Icons.search, size: dense ? 16 : 18),
          prefixIconConstraints: BoxConstraints(
            minWidth: dense ? 34 : 40,
            minHeight: dense ? 32 : 40,
          ),
          suffixIcon: hasValue
              ? IconButton(
                  icon: Icon(Icons.clear, size: dense ? 14 : 16),
                  onPressed: onClear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              : null,
          contentPadding: EdgeInsets.symmetric(
            vertical: dense ? 6 : 10,
            horizontal: dense ? 10 : 14,
          ),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(br),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(br),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(br),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.5,
            ),
          ),
        ),
      );
    if (expand) return field;
    return SizedBox(width: width, child: field);
  }
}

// ── Retail active orders tab ──────────────────────────────────────────────────

class _RetailActiveOrdersTab extends StatelessWidget {
  final List<RetailOrder> orders;
  final bool isDark;
  final bool isMobile;
  final ValueChanged<RetailOrder> onOrderSelected;

  const _RetailActiveOrdersTab({
    required this.orders,
    required this.isDark,
    required this.isMobile,
    required this.onOrderSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48,
                color: isDark ? AppColors.coolGray : AppColors.darkGray),
            const SizedBox(height: AppConstants.spacing16),
            Text(
              'Aucune commande en cours',
              style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Les commandes actives apparaissent ici quand un devis est payé\nou qu\'une vente caisse doit être préparée.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
          ],
        ),
      );
    }

    return _buildOrderList(context, orders, isDark);
  }

  Widget _buildOrderList(
      BuildContext context, List<RetailOrder> orders, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing24,
        AppConstants.spacing4,
        AppConstants.spacing24,
        AppConstants.spacing24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppConstants.spacing8),
              itemBuilder: (_, i) {
                final o = orders[i];
                return _ActiveOrderCard(
                  order: o,
                  isSelected: false,
                  isDark: isDark,
                  inlineClientWithOrder: !isMobile,
                  onTap: () {
                    if (isMobile) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _RetailOrderDetailPage(order: o),
                      ));
                    } else {
                      onOrderSelected(o);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active order card ─────────────────────────────────────────────────────────

class _ActiveOrderCard extends StatelessWidget {
  final RetailOrder order;
  final bool isSelected;
  final bool isDark;
  /// On wide layouts, show client on the same row as the order number.
  final bool inlineClientWithOrder;
  final VoidCallback onTap;

  const _ActiveOrderCard({
    required this.order,
    required this.isSelected,
    required this.isDark,
    this.inlineClientWithOrder = false,
    required this.onTap,
  });

  Color get _statusColor {
    final d = isDark;
    return switch (order.status) {
      RetailOrderStatus.checkPending => AppColors.amber,
      RetailOrderStatus.partiallyPaid => AppColors.boldRed,
      RetailOrderStatus.paid => d ? AppColors.skyBlue : AppColors.primaryBlue,
      RetailOrderStatus.ready => AppColors.amber,
      _ => d ? AppColors.mediumGreen : AppColors.deepGreen,
    };
  }

  @override
  Widget build(BuildContext context) {
    final clientLabel =
        order.clientName?.isNotEmpty == true ? order.clientName! : 'Client de passage';
    final color = _statusColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        child: AnimatedContainer(
          duration: AppConstants.animFast,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.sidebarSelected.withValues(alpha: 0.4)
                    : AppColors.lightBlue)
                : (isDark ? AppColors.darkSurface : AppColors.white),
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            // Uniform border so borderRadius is valid
            border: Border.all(
              color: isDark ? AppColors.darkBorder : const Color(0xFFE8E8E8),
            ),
            boxShadow:
                isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
          ),
          // Left accent strip rendered inside the rounded clip
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(AppConstants.radiusCard - 0.5),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status accent strip
                  AnimatedContainer(
                    duration: AppConstants.animFast,
                    width: 3,
                    color: color,
                  ),
                  // Main card content
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppConstants.spacing16 - 3,
                        vertical: inlineClientWithOrder
                            ? AppConstants.spacing8
                            : AppConstants.spacing12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left: order # (+ client on desktop) + date
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (inlineClientWithOrder)
                                  Row(
                                    children: [
                                      Flexible(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                order.orderNumber,
                                                style: AppTextStyles.body(
                                                  color: isDark
                                                      ? AppColors.skyBlue
                                                      : AppColors.primaryBlue,
                                                ).copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (order.paymentSource ==
                                                RetailPaymentSource
                                                    .paymentLink) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppColors.deepGreen
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.link,
                                                        size: 9,
                                                        color: isDark
                                                            ? AppColors
                                                                .mediumGreen
                                                            : AppColors
                                                                .deepGreen),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      'Lien',
                                                      style: AppTextStyles
                                                              .caption(
                                                                  color: isDark
                                                                      ? AppColors
                                                                          .mediumGreen
                                                                      : AppColors
                                                                          .deepGreen)
                                                          .copyWith(
                                                              fontSize: 9),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6),
                                        child: Text(
                                          '·',
                                          style: AppTextStyles.caption(
                                            color: isDark
                                                ? AppColors.coolGray
                                                : AppColors.darkGray,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          clientLabel,
                                          style: AppTextStyles.body(
                                            color: isDark
                                                ? AppColors.warmWhite
                                                : AppColors.nearBlack,
                                          ).copyWith(fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  Row(
                                    children: [
                                      Text(
                                        order.orderNumber,
                                        style: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.skyBlue
                                              : AppColors.primaryBlue,
                                        ).copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      if (order.paymentSource ==
                                          RetailPaymentSource.paymentLink) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.deepGreen
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.link,
                                                  size: 9,
                                                  color: isDark
                                                      ? AppColors.mediumGreen
                                                      : AppColors.deepGreen),
                                              const SizedBox(width: 3),
                                              Text(
                                                'Lien',
                                                style: AppTextStyles.caption(
                                                  color: isDark
                                                      ? AppColors.mediumGreen
                                                      : AppColors.deepGreen,
                                                ).copyWith(fontSize: 9),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    clientLabel,
                                    style: AppTextStyles.body(
                                      color: isDark
                                          ? AppColors.warmWhite
                                          : AppColors.nearBlack,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(order.paidAt, withTime: true),
                                  style: AppTextStyles.caption(
                                    color: isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Middle: fulfillment + status
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _FulfillmentChipSmall(
                                    mode: order.fulfillmentMode,
                                    isDark: isDark),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    order.status.label,
                                    style: AppTextStyles.caption(color: color)
                                        .copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Right: total + chevron
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.local(
                                    context, order.totalHtg),
                                style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.warmWhite
                                      : AppColors.nearBlack,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(width: AppConstants.spacing8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Active order: print / WhatsApp / email (same UX as completed receipts) ───

void _showActiveOrderWhatsAppDialog(BuildContext context, RetailOrder order) {
  final ctrl = TextEditingController(text: order.clientPhone?.trim() ?? '');
  final errHolder = <String?>[null];
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Envoyer par WhatsApp'),
          content: PhoneField(
            controller: ctrl,
            label: 'Numéro de téléphone',
            errorText: errHolder[0],
            onChanged: (_) => setD(() => errHolder[0] = null),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setD(() => errHolder[0] = 'Veuillez saisir un numéro de téléphone.');
                  return;
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Résumé envoyé par WhatsApp'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    ),
  );
}

void _showActiveOrderEmailDialog(BuildContext context, RetailOrder order) {
  final ctrl = TextEditingController(text: order.clientEmail?.trim() ?? '');
  final errHolder = <String?>[null];
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Envoyer la commande par e-mail'),
          content: TextField(
            controller: ctrl,
            onChanged: (_) => setD(() => errHolder[0] = null),
            decoration: InputDecoration(
              labelText: 'Adresse e-mail',
              hintText: 'email@example.com',
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: errHolder[0],
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusInput)),
            ),
            keyboardType: TextInputType.emailAddress,
            inputFormatters: InputFormatters.email,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final email = ctrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  setD(() => errHolder[0] = 'Veuillez saisir une adresse e-mail valide.');
                  return;
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Résumé envoyé par e-mail'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _showActiveOrderPrintDialog(
  BuildContext context,
  RetailOrder order,
) async {
  try {
    await Printing.layoutPdf(
      name: saleReceiptFilename(order),
      onLayout: (format) => buildSaleReceiptPdf(
        format: format,
        order: order,
        figures: SaleReceiptFigures.fromOrder(order),
        shopName: shopNameFrom(context),
        money: (amount) => localMoney(context, amount),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Le reçu n\'a pas pu être préparé.')),
    );
  }
}

// ── Active order detail panel ─────────────────────────────────────────────────

class _RetailOrderDetailPanel extends ConsumerWidget {
  final RetailOrder order;
  final bool isDark;
  final VoidCallback onClose;
  /// When false, WhatsApp / email / print live only in the parent [AppBar] (mobile).
  final bool showInlineShareActions;

  const _RetailOrderDetailPanel({
    required this.order,
    required this.isDark,
    required this.onClose,
    this.showInlineShareActions = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get latest version from provider
    final current = ref
        .watch(retailOrdersProvider)
        .where((o) => o.id == order.id)
        .firstOrNull;
    if (current == null) {
      return Container(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        child: const Center(child: Text('Commande introuvable')),
      );
    }

    final nextStatus = _nextStatus(current);
    final nextLabel = _nextStatusLabel(current);

    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.orderNumber,
                        style: AppTextStyles.h2(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        _StatusChip(order: current, isDark: isDark),
                        if (current.paymentSource ==
                            RetailPaymentSource.paymentLink) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.deepGreen
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Via le lien',
                                style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.mediumGreen
                                      : AppColors.deepGreen,
                                ).copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                if (showInlineShareActions) ...[
                  IconButton(
                    onPressed: () =>
                        _showActiveOrderWhatsAppDialog(context, current),
                    icon: Icon(Icons.send_outlined,
                        size: 18,
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray),
                    tooltip: 'Partager par WhatsApp',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                  IconButton(
                    onPressed: () =>
                        _showActiveOrderEmailDialog(context, current),
                    icon: Icon(Icons.email_outlined,
                        size: 18,
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray),
                    tooltip: 'Envoyer par e-mail',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                  IconButton(
                    onPressed: () =>
                        _showActiveOrderPrintDialog(context, current),
                    icon: Icon(Icons.print_outlined,
                        size: 18,
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray),
                    tooltip: 'Imprimer',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                ],
                if (showInlineShareActions)
                  AppCloseButton(onPressed: onClose),
              ],
            ),
          ),
          Divider(
              height: 1,
              color:
                  isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE)),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Client
                  _SectionLabel(label: 'Client', isDark: isDark),
                  const SizedBox(height: 8),
                  if (current.clientName?.isNotEmpty ?? false)
                    _InfoRow(
                        icon: Icons.person_outline_rounded,
                        text: current.clientName!,
                        isDark: isDark,
                        bold: true),
                  if (current.clientPhone?.isNotEmpty ?? false)
                    _InfoRow(
                        icon: Icons.phone_outlined,
                        text: current.clientPhone!,
                        isDark: isDark),
                  if (current.clientEmail?.isNotEmpty ?? false)
                    _InfoRow(
                        icon: Icons.email_outlined,
                        text: current.clientEmail!,
                        isDark: isDark),
                  const SizedBox(height: 12),

                  // Fulfillment
                  _SectionLabel(label: 'Remise', isDark: isDark),
                  const SizedBox(height: 8),
                  _FulfillmentChipSmall(
                      mode: current.fulfillmentMode, isDark: isDark),
                  if (current.deliveryLocation?.isNotEmpty ?? false)
                    _InfoRow(
                        icon: Icons.place_outlined,
                        text: current.deliveryLocation!,
                        isDark: isDark),
                  if (current.deliveryPhone?.isNotEmpty ?? false)
                    _InfoRow(
                        icon: Icons.phone_outlined,
                        text: current.deliveryPhone!,
                        isDark: isDark),
                  const SizedBox(height: 12),

                  // Items
                  _SectionLabel(label: 'Articles', isDark: isDark),
                  const SizedBox(height: 8),
                  _LinesTable(
                    rows: current.lines
                        .map((l) => (
                              l.quantity,
                              l.productName,
                              l.unitPriceHtg,
                              l.lineTotalHtg,
                            ))
                        .toList(),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  Divider(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFEEEEEE)),
                  const SizedBox(height: 4),
                  _TotalRowSimple(
                    label: 'Sous-total',
                    amount: current.subtotalHtg,
                    isDark: isDark,
                    context: context,
                  ),
                  const SizedBox(height: 4),
                  if (current.discountPercent > 0) ...[
                    _TotalRowSimple(
                      label:
                          'Remise (${current.discountPercent.toStringAsFixed(0)} %)',
                      amount: -current.discountAmountHtg,
                      isDark: isDark,
                      context: context,
                      isDiscount: true,
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (current.deliveryFee > 0) ...[
                    _TotalRowSimple(
                      label: 'Frais de livraison',
                      amount: current.deliveryFee,
                      isDark: isDark,
                      context: context,
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (current.serviceChargeAmountHtg > 0) ...[
                    _TotalRowSimple(
                      label:
                          'Frais de service (${current.serviceChargePercent.toStringAsFixed(0)} %)',
                      amount: current.serviceChargeAmountHtg,
                      isDark: isDark,
                      context: context,
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (current.taxAmountHtg > 0) ...[
                    _TotalRowSimple(
                      label:
                          'Taxe (${current.taxPercent.toStringAsFixed(0)} %)',
                      amount: current.taxAmountHtg,
                      isDark: isDark,
                      context: context,
                    ),
                    const SizedBox(height: 4),
                  ],
                  _TotalRowSimple(
                    label: 'Total',
                    amount: current.totalHtg,
                    isDark: isDark,
                    context: context,
                    isBold: true,
                  ),
                  if (current.unpaidBalanceHtg > 0.009) ...[
                    const SizedBox(height: 4),
                    _TotalRowSimple(
                      label: saleReceiptPaidLabel(current),
                      amount: current.amountPaidHtg ?? 0,
                      isDark: isDark,
                      context: context,
                      isBold: !saleReceiptCheckAwaitingCredit(current),
                      emphasis: saleReceiptCheckAwaitingCredit(current)
                          ? null
                          : AppColors.deepGreen,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('order-balance-due'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: (saleReceiptCheckAwaitingCredit(current)
                                ? AppColors.amber
                                : AppColors.boldRed)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: saleReceiptCheckAwaitingCredit(current)
                              ? AppColors.amber
                              : AppColors.boldRed,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: saleReceiptCheckAwaitingCredit(current)
                                ? AppColors.amber
                                : AppColors.boldRed,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              saleReceiptBalanceLabel(current),
                              style: AppTextStyles.body(
                                color: saleReceiptCheckAwaitingCredit(current)
                                    ? AppColors.amber
                                    : AppColors.boldRed,
                              ).copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            CurrencyFormatter.local(
                              context,
                              current.unpaidBalanceHtg,
                            ),
                            style: AppTextStyles.price(
                              color: saleReceiptCheckAwaitingCredit(current)
                                  ? AppColors.amber
                                  : AppColors.boldRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Divider(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFEEEEEE)),
                  const SizedBox(height: 8),
                  _SectionLabel(label: 'Paiement', isDark: isDark),
                  const SizedBox(height: 8),
                  PaymentMethodBlock(
                    isDark: isDark,
                    paymentMethod: current.paymentMethod,
                    paymentLastFour: current.paymentLastFour,
                    check: current.paymentMethod == PaymentMethodType.check
                        ? current.checkPayment
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    current.status == RetailOrderStatus.checkPending
                        ? 'Chèque reçu le ${_formatDate(current.createdAt, withTime: true)}'
                        : current.status == RetailOrderStatus.partiallyPaid
                            ? 'Encaissé le ${_formatDate(current.paidAt, withTime: true)}'
                            : 'Payé le ${_formatDate(current.paidAt, withTime: true)}',
                    style: AppTextStyles.caption(
                        color:
                            isDark ? AppColors.coolGray : AppColors.darkGray),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          Divider(
              height: 1,
              color:
                  isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current.checkPayment != null &&
                    !current.checkPayment!.refused) ...[
                  OutlinedButton.icon(
                    key: const Key('edit-check'),
                    onPressed: () => showEditCheckPanel(
                      context,
                      orderId: current.id,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Modifier le chèque'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? AppColors.skyBlue
                          : AppColors.primaryBlue,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusButton,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (current.status == RetailOrderStatus.checkPending &&
                    current.checkPayment != null &&
                    !current.checkPayment!.refused) ...[
                  ElevatedButton.icon(
                    key: const Key('approve-check'),
                    onPressed: () {
                      final error = ref
                          .read(retailOrdersProvider.notifier)
                          .clearCheck(current.id);
                      if (error == null || !context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error)),
                      );
                    },
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Approuver le chèque'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusButton)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('refuse-check'),
                    onPressed: () async {
                      final refuse = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Refuser le chèque'),
                          content: const Text(
                            'Le solde réservé sera annulé et la vente restera impayée.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              key: const Key('refuse-check-confirm'),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Refuser'),
                            ),
                          ],
                        ),
                      );
                      if (refuse != true || !context.mounted) return;
                      ref
                          .read(retailOrdersProvider.notifier)
                          .refuseCheck(current.id);
                    },
                    icon: const Icon(Icons.block, size: 16),
                    label: const Text('Refuser le chèque'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.boldRed,
                      side: const BorderSide(color: AppColors.boldRed),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusButton,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                if (nextStatus != null && nextLabel != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      ref
                          .read(retailOrdersProvider.notifier)
                          .updateStatus(current.id, nextStatus);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text(nextLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusButton)),
                    ),
                  ),
                if (nextStatus != null) const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(retailOrdersProvider.notifier).updateStatus(
                        current.id, RetailOrderStatus.completed);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 16),
                  label: const Text('Marquer terminé'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? AppColors.mediumGreen
                        : AppColors.deepGreen,
                    side: BorderSide(
                        color: isDark
                            ? AppColors.mediumGreen
                            : AppColors.deepGreen),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusButton)),
                  ),
                ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  RetailOrderStatus? _nextStatus(RetailOrder o) {
    switch (o.fulfillmentMode) {
      case RetailFulfillmentMode.inStore:
        return null; // Use "Marquer terminé" only
      case RetailFulfillmentMode.pickup:
        if (o.status == RetailOrderStatus.paid) {
          return RetailOrderStatus.ready;
        }
        if (o.status == RetailOrderStatus.ready) {
          return RetailOrderStatus.pickedUp;
        }
        return null;
      case RetailFulfillmentMode.delivery:
        if (o.status == RetailOrderStatus.paid) {
          return RetailOrderStatus.ready;
        }
        if (o.status == RetailOrderStatus.ready) {
          return RetailOrderStatus.delivered;
        }
        return null;
    }
  }

  String? _nextStatusLabel(RetailOrder o) {
    return switch (_nextStatus(o)) {
      RetailOrderStatus.ready => 'Marquer prêt',
      RetailOrderStatus.pickedUp => 'Marquer retiré',
      RetailOrderStatus.delivered => 'Marquer livré',
      _ => null,
    };
  }
}

/// Full-screen order detail for screens outside Commandes (e.g. Synchronisation).
class RetailOrderDetailPage extends StatelessWidget {
  final RetailOrder order;

  const RetailOrderDetailPage({super.key, required this.order});

  @override
  Widget build(BuildContext context) => _RetailOrderDetailPage(order: order);
}

// ── Mobile full-screen order detail page ─────────────────────────────────────

class _RetailOrderDetailPage extends ConsumerWidget {
  final RetailOrder order;

  const _RetailOrderDetailPage({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = ref
            .watch(retailOrdersProvider)
            .where((o) => o.id == order.id)
            .firstOrNull ??
        order;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      appBar: AppBar(
        title: Text(current.orderNumber, style: AppTextStyles.h3(color: ink)),
        // The app theme paints app bar icons white. This bar is white, so
        // the icon color has to be set or the close button disappears.
        foregroundColor: ink,
        iconTheme: IconThemeData(color: ink),
        leading: AppCloseButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.send_outlined, size: 22),
            tooltip: 'Partager par WhatsApp',
            onPressed: () =>
                _showActiveOrderWhatsAppDialog(context, current),
          ),
          IconButton(
            icon: const Icon(Icons.email_outlined, size: 22),
            tooltip: 'Envoyer par e-mail',
            onPressed: () => _showActiveOrderEmailDialog(context, current),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined, size: 22),
            tooltip: 'Imprimer',
            onPressed: () => _showActiveOrderPrintDialog(context, current),
          ),
        ],
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        elevation: 0,
      ),
      body: _RetailOrderDetailPanel(
        order: current,
        isDark: isDark,
        showInlineShareActions: false,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}

// ── Lines table (Qty / Item / Unit / Total) ───────────────────────────────────

/// Compact POS-style table for order / quote line items.
/// Each [rows] entry is (qty, productName, unitPriceHtg, lineTotalHtg).
class _LinesTable extends StatelessWidget {
  final List<(int, String, double, double)> rows;
  final bool isDark;

  const _LinesTable({required this.rows, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hdrBg =
        isDark ? AppColors.darkBackground : const Color(0xFFEEF2F7);
    final rowBg =
        isDark ? AppColors.darkSurface.withValues(alpha: 0.6) : AppColors.white;
    final divColor =
        isDark ? AppColors.darkBorder : const Color(0xFFE4E8EE);
    final hdrColor =
        isDark ? AppColors.coolGray : AppColors.darkGray;
    final valColor =
        isDark ? AppColors.warmWhite : AppColors.nearBlack;

    TextStyle hdr() => AppTextStyles.caption(color: hdrColor)
        .copyWith(fontWeight: FontWeight.w700, fontSize: 10.5);
    TextStyle val({bool bold = false}) =>
        AppTextStyles.caption(color: valColor).copyWith(
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        );

    Widget headerRow() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: hdrBg,
          child: Row(
            children: [
              SizedBox(
                  width: 28,
                  child:
                      Text('Qté', style: hdr(), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              Expanded(child: Text('Article', style: hdr())),
              SizedBox(
                  width: 70,
                  child:
                      Text('Unité', style: hdr(), textAlign: TextAlign.right)),
              const SizedBox(width: 6),
              SizedBox(
                  width: 70,
                  child:
                      Text('Total', style: hdr(), textAlign: TextAlign.right)),
            ],
          ),
        );

    Widget dataRow(int qty, String name, double unit, double total,
            {bool last = false}) =>
        Container(
          color: rowBg,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('$qty',
                            style: hdr().copyWith(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name,
                          style: val(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(unit),
                          style: val(), textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(total),
                          style: val(bold: true), textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
              if (!last)
                Container(height: 0.5, color: divColor, margin: const EdgeInsets.symmetric(horizontal: 10)),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: divColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          headerRow(),
          Container(height: 1, color: divColor),
          ...rows.asMap().entries.map((e) => dataRow(
                e.value.$1,
                e.value.$2,
                e.value.$3,
                e.value.$4,
                last: e.key == rows.length - 1,
              )),
        ],
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final RetailOrder order;
  final bool isDark;

  const _StatusChip({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = switch (order.status) {
      RetailOrderStatus.checkPending => AppColors.amber,
      RetailOrderStatus.partiallyPaid => AppColors.boldRed,
      RetailOrderStatus.paid =>
        isDark ? AppColors.skyBlue : AppColors.primaryBlue,
      RetailOrderStatus.ready => AppColors.amber,
      _ => isDark ? AppColors.mediumGreen : AppColors.deepGreen,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(order.status.label,
          style: AppTextStyles.caption(color: color)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _FulfillmentChipSmall extends StatelessWidget {
  final RetailFulfillmentMode mode;
  final bool isDark;

  const _FulfillmentChipSmall({required this.mode, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (mode) {
      RetailFulfillmentMode.inStore => (
          Icons.storefront_outlined,
          'En magasin',
          AppColors.primaryBlue
        ),
      RetailFulfillmentMode.pickup => (
          Icons.shopping_bag_outlined,
          'Retrait',
          AppColors.amber
        ),
      RetailFulfillmentMode.delivery => (
          Icons.local_shipping_outlined,
          'Livraison',
          isDark ? AppColors.mediumGreen : AppColors.deepGreen
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style:
                AppTextStyles.caption(color: color).copyWith(fontSize: 11)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;

  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.caption(
              color: isDark ? AppColors.coolGray : AppColors.darkGray)
          .copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;
  final bool bold;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.isDark,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 13,
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(
                  fontWeight:
                      bold ? FontWeight.w600 : FontWeight.normal),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRowSimple extends StatelessWidget {
  final String label;
  final double amount;
  final bool isDark;
  final BuildContext context;
  final bool isBold;
  final bool isDiscount;
  final Color? emphasis;

  const _TotalRowSimple({
    required this.label,
    required this.amount,
    required this.isDark,
    required this.context,
    this.isBold = false,
    this.isDiscount = false,
    this.emphasis,
  });

  @override
  Widget build(BuildContext _) {
    final baseColor = emphasis ??
        (isDiscount
            ? (isDark ? AppColors.mediumGreen : AppColors.deepGreen)
            : (isDark ? AppColors.warmWhite : AppColors.nearBlack));
    final labelColor = emphasis ??
        (isDark ? AppColors.coolGray : AppColors.darkGray);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.body(color: labelColor).copyWith(
            fontWeight: emphasis != null
                ? FontWeight.w700
                : (isBold ? FontWeight.w600 : FontWeight.normal),
          ),
        ),
        Text(
          isDiscount
              ? '- ${CurrencyFormatter.local(context, amount.abs())}'
              : CurrencyFormatter.local(context, amount),
          style:
              (isBold ? AppTextStyles.price() : AppTextStyles.body()).copyWith(
            color: baseColor,
            fontSize: isBold ? 15 : 13,
          ),
        ),
      ],
    );
  }
}

// ── Formatting ────────────────────────────────────────────────────────────────

String _formatDate(DateTime dt, {bool withTime = false}) {
  final months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  final base =
      '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  if (!withTime) return base;
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$base  $h:$m';
}

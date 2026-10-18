import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_hotel_data.dart';
import '../../mock/mock_restaurant_data.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/discount_approval_dialog.dart';
import '../../widgets/list_page_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_close_button.dart';

enum CompletedKitchenOrdersScope { restaurant, hotelRestaurant }

class CompletedKitchenLine {
  final String name;
  final int quantity;
  final String? note;
  const CompletedKitchenLine({required this.name, required this.quantity, this.note});
}

class CompletedKitchenOrderEntry {
  final int orderId;
  final int batchNumber;
  final String orderNumberLabel;
  final String clientName;
  final String orderType;
  final DateTime completedAt;
  final List<CompletedKitchenLine> kitchenLines;
  const CompletedKitchenOrderEntry({
    required this.orderId,
    required this.batchNumber,
    required this.orderNumberLabel,
    required this.clientName,
    required this.orderType,
    required this.completedAt,
    required this.kitchenLines,
  });
}

String _normalizeBatchStatus(String s) => s == 'preparing' ? 'in_progress' : s;

String _formatOrderType(String t) {
  switch (t) {
    case 'dine_in':      return 'Dine-in';
    case 'takeout':      return 'Takeout';
    case 'delivery':     return 'Livraison';
    case 'room_service': return 'Service en chambre';
    case 'reservation':  return 'Reservation';
    default:             return t;
  }
}

IconData _orderTypeIcon(String t) {
  switch (t) {
    case 'dine_in':      return Icons.table_bar_outlined;
    case 'takeout':      return Icons.shopping_bag_outlined;
    case 'delivery':     return Icons.delivery_dining_outlined;
    case 'room_service': return Icons.room_service_outlined;
    case 'reservation':  return Icons.event_seat_outlined;
    default:             return Icons.receipt_long_outlined;
  }
}

String _restaurantClientName(MockOrder o) {
  final c = o.customerName?.trim();
  if (c != null && c.isNotEmpty) return c;
  final r = o.reservationGuestName?.trim();
  if (r != null && r.isNotEmpty) return r;
  if (o.tableName.trim().isNotEmpty) return o.tableName;
  return '—';
}

String _hotelClientName(MockHotelRestaurantOrder o) {
  final g = o.guestName?.trim();
  if (g != null && g.isNotEmpty) return g;
  final r = o.reservationGuestName?.trim();
  if (r != null && r.isNotEmpty) return r;
  final room = o.roomNumber?.trim();
  if (room != null && room.isNotEmpty) return 'Chambre $room';
  final t = o.tableName?.trim();
  if (t != null && t.isNotEmpty) return t;
  return '—';
}

List<CompletedKitchenOrderEntry> _entriesFromRestaurant(List<MockOrder> orders) {
  final out = <CompletedKitchenOrderEntry>[];
  for (final o in orders) {
    for (final b in o.kitchenBatches) {
      final st = _normalizeBatchStatus(b.status);
      if (st != 'complete' && st != 'delivered') continue;
      final lines = b.items.where((i) => !i.isDrink).toList();
      if (lines.isEmpty) continue;
      out.add(CompletedKitchenOrderEntry(
        orderId: o.id,
        batchNumber: b.batchNumber,
        orderNumberLabel: '#${o.id}',
        clientName: _restaurantClientName(o),
        orderType: o.orderType,
        completedAt: b.kitchenCompletedAt ?? b.placedAt,
        kitchenLines: [for (final i in lines) CompletedKitchenLine(name: i.name, quantity: i.quantity, note: i.note)],
      ));
    }
  }
  out.sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return out;
}

List<CompletedKitchenOrderEntry> _entriesFromHotel(List<MockHotelRestaurantOrder> orders) {
  final out = <CompletedKitchenOrderEntry>[];
  for (final o in orders) {
    for (final b in o.kitchenBatches) {
      final st = _normalizeBatchStatus(b.status);
      if (st != 'complete' && st != 'delivered') continue;
      final lines = b.items.where((i) => !i.isDrink).toList();
      if (lines.isEmpty) continue;
      out.add(CompletedKitchenOrderEntry(
        orderId: o.id,
        batchNumber: b.batchNumber,
        orderNumberLabel: '#${o.id}',
        clientName: _hotelClientName(o),
        orderType: o.orderType,
        completedAt: b.kitchenCompletedAt ?? b.placedAt,
        kitchenLines: [for (final i in lines) CompletedKitchenLine(name: i.name, quantity: i.quantity, note: i.note)],
      ));
    }
  }
  out.sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return out;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _canReverseToday(CompletedKitchenOrderEntry e) =>
    _isSameDay(e.completedAt, DateTime.now());

bool _needsAdminForReverse(CompletedKitchenOrderEntry e) =>
    DateTime.now().difference(e.completedAt) > const Duration(hours: 3);

// ── Screen ────────────────────────────────────────────────────────────────────

class CompletedKitchenOrdersScreen extends ConsumerStatefulWidget {
  final CompletedKitchenOrdersScope scope;
  const CompletedKitchenOrdersScreen({super.key, required this.scope});

  @override
  ConsumerState<CompletedKitchenOrdersScreen> createState() =>
      _CompletedKitchenOrdersScreenState();
}

class _CompletedKitchenOrdersScreenState
    extends ConsumerState<CompletedKitchenOrdersScreen> {
  static const int _pageSize = 10;
  final _searchCtrl = TextEditingController();
  DateTime? _filterDate;
  int _pageIndex = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _kitchenRoute => widget.scope == CompletedKitchenOrdersScope.restaurant
      ? AppRoutes.restaurantKitchen
      : AppRoutes.hotelRestaurantKitchen;

  List<CompletedKitchenOrderEntry> _allEntries() {
    switch (widget.scope) {
      case CompletedKitchenOrdersScope.restaurant:
        return _entriesFromRestaurant(ref.watch(mockRestaurantOrdersProvider));
      case CompletedKitchenOrdersScope.hotelRestaurant:
        return _entriesFromHotel(ref.watch(mockHotelRestaurantOrdersProvider));
    }
  }

  List<CompletedKitchenOrderEntry> _filtered(List<CompletedKitchenOrderEntry> all) {
    var list = all;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) =>
          e.orderId.toString().contains(q) ||
          e.clientName.toLowerCase().contains(q) ||
          e.orderNumberLabel.toLowerCase().contains(q)).toList();
    }
    if (_filterDate != null) {
      final d = _filterDate!;
      list = list.where((e) => _isSameDay(e.completedAt, d)).toList();
    }
    return list;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) setState(() { _filterDate = picked; _pageIndex = 0; });
  }

  Future<void> _reverse(CompletedKitchenOrderEntry e, {VoidCallback? popDrawer}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_canReverseToday(e)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Le renvoi n\'est possible que pour les tickets terminés aujourd\'hui.'),
      ));
      return;
    }
    if (_needsAdminForReverse(e)) {
      final ok = await showAdminApprovalDialog(
        context, ref,
        message: 'Terminé il y a plus de 3 heures. Saisissez l\'autorisation admin pour renvoyer.',
        isDark: isDark,
        title: 'Autorisation admin',
      );
      if (ok != true) return;
    }
    switch (widget.scope) {
      case CompletedKitchenOrdersScope.restaurant:
        ref.read(mockRestaurantOrdersProvider.notifier)
            .updateBatchStatus(e.orderId, e.batchNumber, 'pending');
      case CompletedKitchenOrdersScope.hotelRestaurant:
        ref.read(mockHotelRestaurantOrdersProvider.notifier)
            .updateBatchStatus(e.orderId, e.batchNumber, 'pending');
    }
    popDrawer?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ticket renvoyé en cuisine.')),
    );
    context.go(_kitchenRoute);
  }

  void _openDetail(CompletedKitchenOrderEntry e, bool isDark) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Détail du ticket',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: _DetailPanel(
          entry: e,
          isDark: isDark,
          onReverse: () => _reverse(e, popDrawer: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : const Color(0xFFF0F4F8);
    final all = _allEntries();
    final filtered = _filtered(all);
    final pageCount = filtered.isEmpty ? 1 : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _pageIndex.clamp(0, (pageCount - 1).clamp(0, 9999));
    final start = page * _pageSize;
    final pageItems = filtered.isEmpty
        ? <CompletedKitchenOrderEntry>[]
        : filtered.sublist(start, (start + _pageSize).clamp(0, filtered.length));
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.mobileBreakpoint;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            filteredCount: filtered.length,
            isDark: isDark,
            kitchenRoute: _kitchenRoute,
          ),
          _FilterBar(
            searchCtrl: _searchCtrl,
            filterDate: _filterDate,
            isDark: isDark,
            onSearchChanged: () => setState(() => _pageIndex = 0),
            onPickDate: _pickDate,
            onClearDate: () => setState(() { _filterDate = null; _pageIndex = 0; }),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Aucun ticket terminé',
                    message: _searchCtrl.text.trim().isNotEmpty || _filterDate != null
                        ? 'Modifiez la recherche ou le filtre de date.'
                        : 'Les tickets cuisine terminés apparaîtront ici.',
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? AppConstants.spacing24 : AppConstants.spacing12,
                      vertical: AppConstants.spacing12,
                    ),
                    itemCount: pageItems.length +
                        (!wide && pageCount > 1 ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= pageItems.length) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: ListPageNav(
                            isDark: isDark,
                            currentPage: page + 1,
                            totalPages: pageCount,
                            onPrevious: page > 0
                                ? () => setState(() => _pageIndex = page - 1)
                                : null,
                            onNext: page < pageCount - 1
                                ? () => setState(() => _pageIndex = page + 1)
                                : null,
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
                        child: _CompactOrderRow(
                          entry: pageItems[i],
                          isDark: isDark,
                          wide: wide,
                          onTap: () => _openDetail(pageItems[i], isDark),
                          onReverse: () => _reverse(pageItems[i]),
                        ),
                      );
                    },
                  ),
          ),
          if (wide && filtered.isNotEmpty)
            _PaginationBar(
              page: page,
              pageCount: pageCount,
              totalCount: filtered.length,
              isDark: isDark,
              onPrev: page > 0 ? () => setState(() => _pageIndex = page - 1) : null,
              onNext: page < pageCount - 1 ? () => setState(() => _pageIndex = page + 1) : null,
              onPageSelected: (i) => setState(() => _pageIndex = i),
            ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int filteredCount;
  final bool isDark;
  final String kitchenRoute;
  const _Header({required this.filteredCount, required this.isDark, required this.kitchenRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing24,
        vertical: AppConstants.spacing16,
      ),
      color: isDark ? AppColors.darkSurface : AppColors.primaryBlue,
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.white, size: 22),
          const SizedBox(width: AppConstants.spacing12),
          Expanded(
            child: Text(
              'Commandes cuisine terminées',
              style: AppTextStyles.h2(color: AppColors.white),
            ),
          ),
          if (filteredCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$filteredCount ticket${filteredCount == 1 ? '' : 's'}',
                style: AppTextStyles.caption(color: AppColors.white),
              ),
            ),
          const SizedBox(width: AppConstants.spacing12),
          TextButton.icon(
            onPressed: () => context.go(kitchenRoute),
            icon: const Icon(Icons.soup_kitchen_outlined, size: 18, color: AppColors.white),
            label: const Text('Cuisine', style: TextStyle(color: AppColors.white)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final DateTime? filterDate;
  final bool isDark;
  final VoidCallback onSearchChanged;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  const _FilterBar({
    required this.searchCtrl,
    required this.filterDate,
    required this.isDark,
    required this.onSearchChanged,
    required this.onPickDate,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.white;
    final hintColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111E2D) : const Color(0xFFF0F4F8),
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth >= AppConstants.mobileBreakpoint;
        final searchField = _PillTextField(
          controller: searchCtrl,
          hint: 'Rechercher une commande ou un client…',
          icon: Icons.search,
          isDark: isDark,
          surfaceColor: surfaceColor,
          hintColor: hintColor,
          onChanged: (_) => onSearchChanged(),
        );

        final dateBtn = _DateFilterButton(
          filterDate: filterDate,
          isDark: isDark,
          onTap: onPickDate,
          onClear: filterDate != null ? onClearDate : null,
        );

        if (wide) {
          return Row(
            children: [
              Expanded(flex: 3, child: searchField),
              const SizedBox(width: AppConstants.spacing12),
              dateBtn,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchField,
            const SizedBox(height: AppConstants.spacing8),
            dateBtn,
          ],
        );
      }),
    );
  }
}

class _PillTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isDark;
  final Color surfaceColor;
  final Color hintColor;
  final ValueChanged<String> onChanged;

  const _PillTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isDark,
    required this.surfaceColor,
    required this.hintColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.body(color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: hintColor),
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFDCE3EA),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        isDense: true,
        constraints: const BoxConstraints(maxHeight: 42),
      ),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  final DateTime? filterDate;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateFilterButton({
    required this.filterDate,
    required this.isDark,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final active = filterDate != null;
    final bg = active
        ? (isDark ? AppColors.skyBlue.withValues(alpha: 0.25) : AppColors.lightBlue)
        : (isDark ? AppColors.darkSurface : AppColors.white);
    final fg = active
        ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
        : (isDark ? AppColors.coolGray : AppColors.darkGray);
    final border = active
        ? (isDark ? AppColors.skyBlue.withValues(alpha: 0.5) : AppColors.primaryBlue.withValues(alpha: 0.4))
        : (isDark ? AppColors.darkBorder : const Color(0xFFDCE3EA));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  active ? DateFormatter.shortDate(filterDate!) : 'Filtrer par date',
                  style: AppTextStyles.caption(color: fg).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Icon(Icons.close, size: 14, color: fg),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Compact order row card ─────────────────────────────────────────────────────

class _CompactOrderRow extends StatelessWidget {
  final CompletedKitchenOrderEntry entry;
  final bool isDark;
  final bool wide;
  final VoidCallback onTap;
  final VoidCallback onReverse;

  const _CompactOrderRow({
    required this.entry,
    required this.isDark,
    required this.wide,
    required this.onTap,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) {
    final canRev = _canReverseToday(entry);
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE8EEF4);

    final typeIcon = _orderTypeIcon(entry.orderType);
    final typeLabel = _formatOrderType(entry.orderType);
    final typeColor = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final typeBg = isDark
        ? AppColors.skyBlue.withValues(alpha: 0.15)
        : AppColors.lightBlue;

    final timeLabel =
        '${DateFormatter.shortDate(entry.completedAt)} · ${DateFormatter.timeOfDay(entry.completedAt)}';

    Widget reverseBtn() => canRev
        ? InkWell(
            onTap: onReverse,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.amber.withValues(alpha: 0.15)
                    : AppColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.undo, size: 13, color: AppColors.amber),
                  const SizedBox(width: 4),
                  Text('Renvoyer',
                      style: AppTextStyles.caption(color: AppColors.amber)
                          .copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          )
        : Tooltip(
            message: 'Réservé aux tickets terminés aujourd\'hui',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: (isDark ? AppColors.coolGray : const Color(0xFFCCCCCC))
                        .withValues(alpha: 0.4)),
              ),
              child: Text('Pas aujourd\'hui',
                  style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : const Color(0xFFAAAAAA))),
            ),
          );

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          ),
          child: wide
              ? _WideLayout(
                  entry: entry,
                  typeIcon: typeIcon,
                  typeLabel: typeLabel,
                  typeColor: typeColor,
                  typeBg: typeBg,
                  timeLabel: timeLabel,
                  isDark: isDark,
                  reverseBtn: reverseBtn(),
                )
              : _NarrowLayout(
                  entry: entry,
                  typeIcon: typeIcon,
                  typeLabel: typeLabel,
                  typeColor: typeColor,
                  typeBg: typeBg,
                  timeLabel: timeLabel,
                  isDark: isDark,
                  reverseBtn: reverseBtn(),
                ),
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  final CompletedKitchenOrderEntry entry;
  final IconData typeIcon;
  final String typeLabel;
  final Color typeColor;
  final Color typeBg;
  final String timeLabel;
  final bool isDark;
  final Widget reverseBtn;

  const _WideLayout({
    required this.entry,
    required this.typeIcon,
    required this.typeLabel,
    required this.typeColor,
    required this.typeBg,
    required this.timeLabel,
    required this.isDark,
    required this.reverseBtn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Order #
          SizedBox(
            width: 72,
            child: Text(
              entry.orderNumberLabel,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          // Type chip
          SizedBox(
            width: 140,
            child: _TypeChip(icon: typeIcon, label: typeLabel, color: typeColor, bg: typeBg),
          ),
          // Client
          Expanded(
            child: Text(
              entry.clientName,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Time
          SizedBox(
            width: 170,
            child: Text(
              timeLabel,
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
          ),
          // Action
          reverseBtn,
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 18,
              color: isDark ? AppColors.coolGray : const Color(0xFFBBBBBB)),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final CompletedKitchenOrderEntry entry;
  final IconData typeIcon;
  final String typeLabel;
  final Color typeColor;
  final Color typeBg;
  final String timeLabel;
  final bool isDark;
  final Widget reverseBtn;

  const _NarrowLayout({
    required this.entry,
    required this.typeIcon,
    required this.typeLabel,
    required this.typeColor,
    required this.typeBg,
    required this.timeLabel,
    required this.isDark,
    required this.reverseBtn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.orderNumberLabel,
                style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              _TypeChip(icon: typeIcon, label: typeLabel, color: typeColor, bg: typeBg),
              const Spacer(),
              reverseBtn,
            ],
          ),
          const SizedBox(height: 5),
          Text(entry.clientName,
              style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
          const SizedBox(height: 3),
          Text(timeLabel,
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  const _TypeChip({required this.icon, required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.caption(color: color).copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int page;
  final int pageCount;
  final int totalCount;
  final bool isDark;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int> onPageSelected;

  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.totalCount,
    required this.isDark,
    this.onPrev,
    this.onNext,
    required this.onPageSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111E2D) : const Color(0xFFF0F4F8),
        border: Border(top: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0),
        )),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageBtn(icon: Icons.chevron_left, onTap: onPrev, isDark: isDark),
          const SizedBox(width: AppConstants.spacing12),
          // Page numbers
          for (var i = 0; i < pageCount; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _PageDot(
              number: i + 1,
              selected: i == page,
              isDark: isDark,
              onTap: i != page ? () => onPageSelected(i) : null,
            ),
          ],
          const SizedBox(width: AppConstants.spacing12),
          _PageBtn(icon: Icons.chevron_right, onTap: onNext, isDark: isDark),
          const Spacer(),
          Text(
            '$totalCount total',
            style: AppTextStyles.caption(color: fg),
          ),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;
  const _PageBtn({required this.icon, this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? (isDark ? AppColors.warmWhite : AppColors.nearBlack)
        : (isDark ? AppColors.coolGray.withValues(alpha: 0.4) : const Color(0xFFCCCCCC));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD)),
          color: isDark ? AppColors.darkSurface : AppColors.white,
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  final int number;
  final bool selected;
  final bool isDark;
  final VoidCallback? onTap;
  const _PageDot({required this.number, required this.selected, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryBlue
              : (isDark ? AppColors.darkSurface : AppColors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.primaryBlue
                : (isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD)),
          ),
        ),
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.white : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detail panel ──────────────────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final CompletedKitchenOrderEntry entry;
  final bool isDark;
  final VoidCallback onReverse;
  const _DetailPanel({required this.entry, required this.isDark, required this.onReverse});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).width * 0.42).clamp(320.0, 440.0);
    final canRev = _canReverseToday(entry);
    final needsAdmin = _needsAdminForReverse(entry);
    final surface = isDark ? AppColors.darkSurface : AppColors.white;

    return Material(
      elevation: 12,
      child: Container(
        width: w,
        height: MediaQuery.sizeOf(context).height,
        color: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FB),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24,
                vertical: AppConstants.spacing16,
              ),
              color: isDark ? AppColors.darkSurface : AppColors.primaryBlue,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.orderNumberLabel,
                            style: AppTextStyles.h2(color: AppColors.white)),
                        const SizedBox(height: 2),
                        Text(_formatOrderType(entry.orderType),
                            style: AppTextStyles.caption(color: AppColors.sidebarIcon)),
                      ],
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta cards
                    Row(
                      children: [
                        Expanded(
                          child: _MetaCard(
                            icon: Icons.person_outline,
                            label: 'Client',
                            value: entry.clientName,
                            isDark: isDark,
                            surface: surface,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing12),
                        Expanded(
                          child: _MetaCard(
                            icon: Icons.check_circle_outline,
                            label: 'Terminé',
                            value: '${DateFormatter.shortDate(entry.completedAt)}\n'
                                '${DateFormatter.timeOfDay(entry.completedAt)}',
                            isDark: isDark,
                            surface: surface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacing16),
                    // Kitchen lines
                    Text('Articles cuisine',
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.coolGray : AppColors.darkGray,
                        ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppConstants.spacing8),
                    Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : const Color(0xFFE8EEF4),
                        ),
                      ),
                      child: Column(
                        children: [
                          for (var idx = 0; idx < entry.kitchenLines.length; idx++) ...[
                            if (idx > 0) Divider(height: 1,
                                color: isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE)),
                            _KitchenLineRow(line: entry.kitchenLines[idx], isDark: isDark),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkBorder : const Color(0xFFE8EEF4),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canRev)
                    _StatusNote(
                      icon: Icons.block_outlined,
                      text: 'Le renvoi n\'est possible que pour les tickets terminés aujourd\'hui.',
                      color: AppColors.boldRed,
                    )
                  else if (needsAdmin)
                    _StatusNote(
                      icon: Icons.admin_panel_settings_outlined,
                      text: 'Terminé depuis plus de 3 heures — approbation admin requise.',
                      color: AppColors.amber,
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: canRev ? onReverse : null,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Renvoyer en cuisine'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color surface;
  const _MetaCard({required this.icon, required this.label, required this.value, required this.isDark, required this.surface});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: isDark ? AppColors.coolGray : AppColors.darkGray),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption(color: isDark ? AppColors.coolGray : AppColors.darkGray)),
          ]),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.body(color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
        ],
      ),
    );
  }
}

class _KitchenLineRow extends StatelessWidget {
  final CompletedKitchenLine line;
  final bool isDark;
  const _KitchenLineRow({required this.line, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('${line.quantity}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  )),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name,
                    style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
                if (line.note != null && line.note!.trim().isNotEmpty)
                  Text('⚠ ${line.note}',
                      style: AppTextStyles.caption(color: AppColors.amber)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _StatusNote({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppTextStyles.caption(color: color))),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_hotel_data.dart';
import '../../mock/mock_reservation_data.dart';
import '../../mock/mock_restaurant_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../app_bottom_sheet.dart';
import '../app_button.dart';
import '../empty_state.dart';
import '../table_picker_modal.dart';
import 'preorder_menu_picker_sheet.dart';
import 'preorder_table.dart';

enum _ResFilter { all, today, upcoming, confirmed, pending }

// ─────────────────────────────────────────────────────────────────────────────
// Hub (list screen)
// ─────────────────────────────────────────────────────────────────────────────

/// Shared reservations UI for restaurant and hotel/restaurant modules.
class ReservationHub extends ConsumerStatefulWidget {
  const ReservationHub({
    super.key,
    required this.reservationsProvider,
    required this.isHotel,
    required this.ordersRoute,
  });

  final StateNotifierProvider<DiningReservationsNotifier, List<MockDiningReservation>>
      reservationsProvider;
  final bool isHotel;
  final String ordersRoute;

  @override
  ConsumerState<ReservationHub> createState() => _ReservationHubState();
}

class _ReservationHubState extends ConsumerState<ReservationHub> {
  _ResFilter _filter = _ResFilter.all;
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// Inline cancel confirmation (no [showDialog]) — avoids mouse_tracker issues on desktop.
  int? _cancelConfirmId;
  String? _cancelConfirmGuestName;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering ──

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _afterToday(DateTime a) {
    final t = DateTime.now();
    return DateTime(a.year, a.month, a.day)
        .isAfter(DateTime(t.year, t.month, t.day));
  }

  List<MockDiningReservation> _applyFilters(List<MockDiningReservation> all) {
    var list = all
        .where((r) => r.status == 'pending' || r.status == 'confirmed')
        .toList();
    final now = DateTime.now();
    switch (_filter) {
      case _ResFilter.today:
        list = list.where((r) => _sameDay(r.reservationAt, now)).toList();
        break;
      case _ResFilter.upcoming:
        list = list.where((r) => _afterToday(r.reservationAt)).toList();
        break;
      case _ResFilter.confirmed:
        list = list.where((r) => r.status == 'confirmed').toList();
        break;
      case _ResFilter.pending:
        list = list.where((r) => r.status == 'pending').toList();
        break;
      case _ResFilter.all:
        break;
    }
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) =>
              r.guestName.toLowerCase().contains(q) ||
              r.phone.contains(q) ||
              '${r.id}'.contains(q))
          .toList();
    }
    list.sort((a, b) => a.reservationAt.compareTo(b.reservationAt));
    return list;
  }

  // ── Actions ──

  void _showDrawer(BuildContext context, {MockDiningReservation? reservation}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: reservation == null ? 'New Reservation' : 'Reservation',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: _ReservationDrawerContent(
          reservationsProvider: widget.reservationsProvider,
          isHotel: widget.isHotel,
          isDark: isDark,
          reservation: reservation,
          onActivated: () {
            if (mounted) context.go(widget.ordersRoute);
          },
        ),
      ),
    );
    });
  }

  Future<void> _activateCard(BuildContext context, int reservationId) async {
    final table = await showTablePickerModal(context, ref);
    if (table == null || !mounted) return;
    if (widget.isHotel) {
      ref.read(widget.reservationsProvider.notifier).activateToHotelRestaurantOrder(
            reservationId: reservationId,
            tableId: table.id,
            tableName: table.name,
            ref: ref,
          );
    } else {
      ref.read(widget.reservationsProvider.notifier).activateToRestaurantOrder(
            reservationId: reservationId,
            tableId: table.id,
            tableName: table.name,
            ref: ref,
          );
    }
    if (!context.mounted) return;
    context.go(widget.ordersRoute);
  }

  void _openCancelConfirm(MockDiningReservation r) {
    setState(() {
      _cancelConfirmId = r.id;
      _cancelConfirmGuestName = r.guestName;
    });
  }

  void _closeCancelConfirm() {
    setState(() {
      _cancelConfirmId = null;
      _cancelConfirmGuestName = null;
    });
  }

  void _performHubCancel() {
    final id = _cancelConfirmId;
    if (id == null || !mounted) return;
    ref.read(widget.reservationsProvider.notifier).cancel(id);
    _closeCancelConfirm();
  }

  Widget _buildHubCancelOverlay(bool isDark, Color muted) {
    final surfaceBg = isDark ? AppColors.darkSurface : AppColors.white;
    final guest = _cancelConfirmGuestName ?? '';

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeCancelConfirm,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: surfaceBg,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.cancel_outlined,
                                size: 22, color: AppColors.error),
                          ),
                          const SizedBox(width: AppConstants.spacing12),
                          Expanded(
                            child: Text(
                              'Cancel reservation?',
                              style: AppTextStyles.h2(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        guest.isNotEmpty
                            ? 'Cancel reservation for $guest? This will remove it from the active list. This cannot be undone.'
                            : 'This reservation will be marked as cancelled and removed from the active list. This action cannot be undone.',
                        style: AppTextStyles.body(color: muted),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _closeCancelConfirm,
                            style: TextButton.styleFrom(foregroundColor: muted),
                            child:
                                Text('Keep it', style: AppTextStyles.button(color: muted)),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'Yes, cancel',
                            icon: Icons.cancel_outlined,
                            variant: AppButtonVariant.danger,
                            fullWidth: false,
                            width: 130,
                            onPressed: _performHubCancel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Filter / search helpers ──

  Widget _buildFilterChips(bool isDark) {
    return Row(
      children: [
        for (final f in _ResFilter.values) ...[
          _ResFilterChip(
            label: _filterLabel(f),
            icon: _filterIcon(f),
            selected: _filter == f,
            isDark: isDark,
            onTap: () => setState(() => _filter = f),
          ),
          if (f != _ResFilter.pending) const SizedBox(width: AppConstants.spacing8),
        ],
      ],
    );
  }

  Widget _buildSearchField(bool isDark, Color primary) {
    return TextField(
      controller: _searchCtrl,
      style: AppTextStyles.caption(),
      textAlignVertical: TextAlignVertical.center,
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search name, phone, ID…',
        hintStyle:
            AppTextStyles.caption(color: isDark ? AppColors.coolGray : AppColors.darkGray),
        prefixIcon: Icon(Icons.search, size: 16,
            color: isDark ? AppColors.coolGray : primary),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
              color: isDark
                  ? AppColors.skyBlue.withValues(alpha: 0.25)
                  : AppColors.primaryBlue.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide:
              BorderSide(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
        ),
        isDense: true,
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.white,
      ),
    );
  }

  String _filterLabel(_ResFilter f) {
    switch (f) {
      case _ResFilter.all:       return 'All';
      case _ResFilter.today:     return 'Today';
      case _ResFilter.upcoming:  return 'Upcoming';
      case _ResFilter.confirmed: return 'Confirmed';
      case _ResFilter.pending:   return 'Pending';
    }
  }

  IconData _filterIcon(_ResFilter f) {
    switch (f) {
      case _ResFilter.all:       return Icons.list_outlined;
      case _ResFilter.today:     return Icons.today_outlined;
      case _ResFilter.upcoming:  return Icons.calendar_month_outlined;
      case _ResFilter.confirmed: return Icons.check_circle_outline;
      case _ResFilter.pending:   return Icons.hourglass_empty_outlined;
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(widget.reservationsProvider);
    final filtered = _applyFilters(all);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    final totalActive =
        all.where((r) => r.status == 'pending' || r.status == 'confirmed').length;
    const desktopCardHeight = 210.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing24, AppConstants.spacing24, AppConstants.spacing24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reservations',
                        style: AppTextStyles.h1(
                          color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$totalActive active · ${filtered.length} shown',
                        style: AppTextStyles.caption(
                            color: isDark ? AppColors.coolGray : AppColors.darkGray),
                      ),
                    ],
                  ),
                ),
                AppButton(
                  label: 'New reservation',
                  icon: Icons.add,
                  onPressed: () => _showDrawer(context),
                  fullWidth: false,
                  width: 160,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppConstants.spacing16),

          // ── Filter chips + search (same row on desktop) ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppConstants.spacing24),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildFilterChips(isDark),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing12),
                      SizedBox(
                        width: 260,
                        height: 36,
                        child: _buildSearchField(isDark, primary),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildFilterChips(isDark),
                      ),
                      const SizedBox(height: AppConstants.spacing12),
                      SizedBox(
                        height: 40,
                        child: _buildSearchField(isDark, primary),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: AppConstants.spacing16),

          // ── Cards ──
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.event_seat_outlined,
                    title: _search.isNotEmpty
                        ? 'No reservations match "$_search"'
                        : 'No reservations',
                    message: _search.isNotEmpty
                        ? 'Try a different name, phone, or ID.'
                        : 'Tap "New reservation" to add the first one.',
                    actionLabel: _search.isEmpty ? 'New reservation' : null,
                    onAction: _search.isEmpty ? () => _showDrawer(context) : null,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacing24,
                      0,
                      AppConstants.spacing24,
                      AppConstants.spacing24,
                    ),
                    itemCount: wide ? (filtered.length / 2).ceil() : filtered.length,
                    itemBuilder: (ctx, rowIndex) {
                      if (!wide) {
                        final r = filtered[rowIndex];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
                          child: _ReservationCard(
                            reservation: r,
                            isDark: isDark,
                            onTap: () => _showDrawer(context, reservation: r),
                            onConfirm: r.status == 'pending'
                                ? () => ref
                                    .read(widget.reservationsProvider.notifier)
                                    .confirm(r.id)
                                : null,
                            onCancel: () => _openCancelConfirm(r),
                            onActivate: () => _activateCard(context, r.id),
                          ),
                        );
                      }
                      // Desktop — two cards per row at equal height
                      final left = filtered[rowIndex * 2];
                      final rightIndex = rowIndex * 2 + 1;
                      final right = rightIndex < filtered.length
                          ? filtered[rightIndex]
                          : null;

                  Widget cardWidget(MockDiningReservation r) => _ReservationCard(
                        reservation: r,
                        isDark: isDark,
                        stretchContent: true,
                        onTap: () => _showDrawer(context, reservation: r),
                        onConfirm: r.status == 'pending'
                            ? () => ref
                                .read(widget.reservationsProvider.notifier)
                                .confirm(r.id)
                            : null,
                        onCancel: () => _openCancelConfirm(r),
                        onActivate: () => _activateCard(context, r.id),
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: desktopCardHeight,
                                child: cardWidget(left),
                              ),
                            ),
                            if (right != null) ...[
                              const SizedBox(width: AppConstants.spacing8),
                              Expanded(
                                child: SizedBox(
                                  height: desktopCardHeight,
                                  child: cardWidget(right),
                                ),
                              ),
                            ] else
                              const Expanded(child: SizedBox()),
                          ],
                        ),
                      );
                    },
                  ),
          ),
            ],
          ),
          if (_cancelConfirmId != null)
            Positioned.fill(
              child: _buildHubCancelOverlay(isDark, muted),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer content
// ─────────────────────────────────────────────────────────────────────────────

class _ReservationDrawerContent extends ConsumerStatefulWidget {
  const _ReservationDrawerContent({
    required this.reservationsProvider,
    required this.isHotel,
    required this.isDark,
    required this.reservation,
    required this.onActivated,
  });

  final StateNotifierProvider<DiningReservationsNotifier, List<MockDiningReservation>>
      reservationsProvider;
  final bool isHotel;
  final bool isDark;
  final MockDiningReservation? reservation;
  final VoidCallback onActivated;

  @override
  ConsumerState<_ReservationDrawerContent> createState() =>
      _ReservationDrawerContentState();
}

class _ReservationDrawerContentState
    extends ConsumerState<_ReservationDrawerContent> {
  late bool _isCreate;
  late bool _panelEdit;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _purposeCtrl;
  late final TextEditingController _notesCtrl;
  late int _adults;
  late int _children;
  late DateTime _reservationDate;
  late TimeOfDay _reservationTime;
  late List<MockDiningReservationPreOrderItem> _draftPreOrder;
  String? _linkedRoomNumber;

  /// Inline editor over the drawer — avoids a second [showDialog] route, which
  /// can trigger `mouse_tracker` re-entrancy on desktop when nested in [showGeneralDialog].
  bool _customItemEditorOpen = false;
  int? _customEditIndex;
  TextEditingController? _customNameCtrl;
  TextEditingController? _customQtyCtrl;
  TextEditingController? _customPriceCtrl;
  TextEditingController? _customNoteCtrl;
  bool _customIsFood = true;

  bool _drawerCancelOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    final r = widget.reservation;
    _isCreate = r == null;
    _panelEdit = r == null;

    _nameCtrl = TextEditingController(text: r?.guestName ?? '');
    _phoneCtrl = TextEditingController(text: r?.phone ?? '');
    _purposeCtrl = TextEditingController(text: r?.purpose ?? '');
    _notesCtrl = TextEditingController(text: r?.specialNotes ?? '');
    _adults = r?.adults ?? 2;
    _children = r?.children ?? 0;
    _reservationDate =
        r?.reservationAt ?? DateTime.now().add(const Duration(days: 1));
    _reservationTime = r != null
        ? TimeOfDay.fromDateTime(r.reservationAt)
        : const TimeOfDay(hour: 19, minute: 0);
    _draftPreOrder = r != null ? List.from(r.preOrderItems) : [];
    _linkedRoomNumber = r?.linkedRoomNumber;
  }

  @override
  void dispose() {
    _disposeCustomItemEditors();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _disposeCustomItemEditors() {
    _customNameCtrl?.dispose();
    _customQtyCtrl?.dispose();
    _customPriceCtrl?.dispose();
    _customNoteCtrl?.dispose();
    _customNameCtrl = null;
    _customQtyCtrl = null;
    _customPriceCtrl = null;
    _customNoteCtrl = null;
  }

  void _closeCustomItemEditor() {
    _disposeCustomItemEditors();
    if (mounted) {
      setState(() {
        _customItemEditorOpen = false;
        _customEditIndex = null;
      });
    }
  }

  MockDiningReservation? _liveReservationFromProvider() {
    final w = widget.reservation;
    if (w == null) return null;
    try {
      return ref.read(widget.reservationsProvider).firstWhere((x) => x.id == w.id);
    } catch (_) {
      return w;
    }
  }

  List<MockDiningReservationPreOrderItem> _preOrderSource(MockDiningReservation? r) {
    if (_isCreate || _panelEdit) return _draftPreOrder;
    if (r != null) return r.preOrderItems;
    return _draftPreOrder;
  }

  /// Pre-order lines can be managed without opening the main **Edit** form,
  /// except when the reservation is cancelled.
  bool _canEditPreOrder(MockDiningReservation? r) {
    if (_isCreate) return true;
    if (r == null) return false;
    return r.status != 'cancelled';
  }

  void _mutatePreOrder(void Function(List<MockDiningReservationPreOrderItem> list) fn) {
    final r = _liveReservationFromProvider();
    if (_isCreate || (r != null && _panelEdit)) {
      setState(() {
        final list = List<MockDiningReservationPreOrderItem>.from(_draftPreOrder);
        fn(list);
        _draftPreOrder = list;
      });
    } else if (r != null && r.status != 'cancelled') {
      final list = List<MockDiningReservationPreOrderItem>.from(r.preOrderItems);
      fn(list);
      ref.read(widget.reservationsProvider.notifier).updatePreOrderItems(r.id, list);
    }
  }

  void _openCustomItemEditor() {
    if (!mounted) return;
    _disposeCustomItemEditors();
    _customEditIndex = null;
    _customNameCtrl = TextEditingController();
    _customQtyCtrl = TextEditingController(text: '1');
    _customPriceCtrl = TextEditingController();
    _customNoteCtrl = TextEditingController();
    _customIsFood = true;
    setState(() => _customItemEditorOpen = true);
  }

  void _openCustomItemEditorForEdit(int index) {
    if (!mounted) return;
    final r = _liveReservationFromProvider();
    final items = _preOrderSource(r);
    if (index < 0 || index >= items.length) return;
    final p = items[index];
    if (p.customItem == null) return;
    final c = p.customItem!;
    _disposeCustomItemEditors();
    _customEditIndex = index;
    _customNameCtrl = TextEditingController(text: c.name);
    _customQtyCtrl = TextEditingController(text: '${c.quantity}');
    _customPriceCtrl = TextEditingController(text: '${c.priceHtg}');
    _customNoteCtrl = TextEditingController(text: c.note ?? '');
    _customIsFood = c.isFood;
    setState(() => _customItemEditorOpen = true);
  }

  void _submitCustomItem() {
    final name = _customNameCtrl?.text.trim() ?? '';
    final qty = int.tryParse(_customQtyCtrl?.text ?? '') ?? 1;
    final price =
        double.tryParse(_customPriceCtrl?.text.replaceAll(',', '.') ?? '') ?? 0;
    final noteTxt = _customNoteCtrl?.text.trim() ?? '';
    final note = noteTxt.isEmpty ? null : noteTxt;
    if (name.isEmpty) return;
    final editIdx = _customEditIndex;
    final r0 = _liveReservationFromProvider();
    final src = _preOrderSource(r0);
    final newId = editIdx != null && editIdx < src.length && src[editIdx].customItem != null
        ? src[editIdx].customItem!.id
        : _nextCustomItemId();
    final newCustom = MockDiningReservationCustomItem(
      id: newId,
      name: name,
      quantity: qty,
      priceHtg: price,
      note: note,
      isFood: _customIsFood,
    );
    _disposeCustomItemEditors();
    if (!mounted) return;
    if (editIdx != null) {
      final sent = editIdx < src.length ? src[editIdx].kitchenSent : false;
      _mutatePreOrder((list) {
        if (editIdx < list.length) {
          list[editIdx] = MockDiningReservationPreOrderItem.custom(newCustom, kitchenSent: sent);
        }
      });
    } else {
      _mutatePreOrder((list) {
        list.add(MockDiningReservationPreOrderItem.custom(newCustom));
      });
    }
    setState(() {
      _customItemEditorOpen = false;
      _customEditIndex = null;
    });
  }

  void _sendFoodToKitchen(MockDiningReservation? r) {
    if (r == null) return;
    final ok = ref.read(widget.reservationsProvider.notifier).sendPreOrderFoodToKitchen(
          reservationId: r.id,
          ref: ref,
          isHotel: widget.isHotel,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Food items sent to the kitchen.' : 'No new food items to send (drinks and items already sent are skipped).',
        ),
      ),
    );
  }

  Future<void> _printPreOrder() async {
    final r = _liveReservationFromProvider();
    final items = _preOrderSource(r);
    if (items.isEmpty) return;
    if (r != null) {
      await printReservationPreOrderSlip(
        context,
        reservation: r.copyWith(preOrderItems: items),
      );
      return;
    }
    if (!_isCreate) return;
    final at = DateTime(
      _reservationDate.year,
      _reservationDate.month,
      _reservationDate.day,
      _reservationTime.hour,
      _reservationTime.minute,
    );
    await printReservationPreOrderSlip(
      context,
      reservation: MockDiningReservation(
        id: 0,
        guestName: _nameCtrl.text.trim().isEmpty ? 'Guest' : _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? '—' : _phoneCtrl.text.trim(),
        adults: _adults,
        children: _children,
        reservationAt: at,
        purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
        specialNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        status: 'pending',
        preOrderItems: List.from(_draftPreOrder),
        linkedRoomNumber: widget.isHotel ? _linkedRoomNumber : null,
      ),
    );
  }

  // ── Save / update ──

  void _saveCreate() {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) return;
    final at = DateTime(
      _reservationDate.year,
      _reservationDate.month,
      _reservationDate.day,
      _reservationTime.hour,
      _reservationTime.minute,
    );
    ref.read(widget.reservationsProvider.notifier).add(
          MockDiningReservation(
            id: 0,
            guestName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            adults: _adults,
            children: _children,
            reservationAt: at,
            purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
            specialNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            status: 'pending',
            preOrderItems: List.from(_draftPreOrder),
            linkedRoomNumber: widget.isHotel ? _linkedRoomNumber : null,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  void _saveUpdate() {
    final r = widget.reservation;
    if (r == null) return;
    final at = DateTime(
      _reservationDate.year,
      _reservationDate.month,
      _reservationDate.day,
      _reservationTime.hour,
      _reservationTime.minute,
    );
    ref.read(widget.reservationsProvider.notifier).update(
          r.copyWith(
            guestName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            adults: _adults,
            children: _children,
            reservationAt: at,
            purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
            specialNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            preOrderItems: List.from(_draftPreOrder),
            linkedRoomNumber: widget.isHotel ? _linkedRoomNumber : null,
          ),
        );
    setState(() => _panelEdit = false);
  }

  Future<void> _activate() async {
    final table =
        await showTablePickerModal(context, ref, useRootNavigator: false);
    if (table == null || !mounted) return;
    final id = widget.reservation!.id;
    if (widget.isHotel) {
      ref.read(widget.reservationsProvider.notifier).activateToHotelRestaurantOrder(
            reservationId: id,
            tableId: table.id,
            tableName: table.name,
            ref: ref,
          );
    } else {
      ref.read(widget.reservationsProvider.notifier).activateToRestaurantOrder(
            reservationId: id,
            tableId: table.id,
            tableName: table.name,
            ref: ref,
          );
    }
    if (mounted) {
      Navigator.of(context).pop();
      widget.onActivated();
    }
  }

  void _openDrawerCancelOverlay() {
    setState(() => _drawerCancelOverlayOpen = true);
  }

  void _closeDrawerCancelOverlay() {
    setState(() => _drawerCancelOverlayOpen = false);
  }

  void _performDrawerCancel() {
    final id = widget.reservation?.id;
    if (id == null || !mounted) return;
    ref.read(widget.reservationsProvider.notifier).cancel(id);
    Navigator.of(context).pop();
  }

  Widget _buildDrawerCancelOverlay(Color muted) {
    final isDark = widget.isDark;
    final surfaceBg = isDark ? AppColors.darkSurface : AppColors.white;
    final guest = widget.reservation?.guestName ?? '';

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeDrawerCancelOverlay,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: surfaceBg,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.cancel_outlined,
                                size: 22, color: AppColors.error),
                          ),
                          const SizedBox(width: AppConstants.spacing12),
                          Expanded(
                            child: Text(
                              'Cancel reservation?',
                              style: AppTextStyles.h2(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        guest.isNotEmpty
                            ? 'Cancel reservation for $guest? This will remove it from the active list. This cannot be undone.'
                            : 'This reservation will be marked as cancelled and removed from the active list. This action cannot be undone.',
                        style: AppTextStyles.body(color: muted),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _closeDrawerCancelOverlay,
                            style: TextButton.styleFrom(foregroundColor: muted),
                            child:
                                Text('Keep it', style: AppTextStyles.button(color: muted)),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'Yes, cancel',
                            icon: Icons.cancel_outlined,
                            variant: AppButtonVariant.danger,
                            fullWidth: false,
                            width: 130,
                            onPressed: _performDrawerCancel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _reservationDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() => _reservationDate = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: _reservationTime,
    );
    if (t != null && mounted) setState(() => _reservationTime = t);
  }

  int _nextCustomItemId() {
    var m = 0;
    for (final p in _preOrderSource(_liveReservationFromProvider())) {
      final c = p.customItem;
      if (c != null && c.id > m) m = c.id;
    }
    return m + 1;
  }

  void _showAddPreOrderItemsSheet(
      BuildContext context, Color primary, Color muted, bool isDark) {
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add items to the order',
              style: AppTextStyles.h2(color: textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'From menu adds the item immediately. Custom opens the item form.',
              style: AppTextStyles.caption(color: muted),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restaurant_menu, color: primary),
              title: Text('From menu', style: AppTextStyles.body(color: textPrimary)),
              subtitle: Text(
                'Choose a menu item',
                style: AppTextStyles.caption(color: muted),
              ),
              onTap: () {
                Navigator.pop(context);
                _addFromMenu();
              },
            ),
            Divider(height: 1, color: muted.withValues(alpha: 0.25)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_note, color: AppColors.amber),
              title:
                  Text('Custom item', style: AppTextStyles.body(color: textPrimary)),
              subtitle: Text(
                'Name, qty, price, food or drink',
                style: AppTextStyles.caption(color: muted),
              ),
              onTap: () {
                Navigator.pop(context);
                _openCustomItemEditor();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addFromMenu() {
    if (!mounted) return;
    final isDark = widget.isDark;
    final menu = ref.read(mockMenuProvider).where((m) => m.available).toList();
    showPreOrderMenuPickerSheet(
      context: context,
      menuItems: menu,
      getPreOrderItems: () => _preOrderSource(_liveReservationFromProvider()),
      isDark: isDark,
      onItemAdded: (m) {
        _mutatePreOrder((list) {
          mergeOrAddCatalogMenuItemToPreOrder(list, m);
        });
      },
    );
  }

  Widget _buildCustomItemOverlay(Color primary, Color surfaceBg, Color muted) {
    final isDark = widget.isDark;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(color: primary, width: 2),
    );

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeCustomItemEditor,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: surfaceBg,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.edit_note, size: 20, color: AppColors.amber),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _customEditIndex != null
                                  ? 'Edit custom item'
                                  : 'Custom item',
                              style: AppTextStyles.h2(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Description', style: AppTextStyles.inputLabel()),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _customNameCtrl,
                          autofocus: true,
                          style: AppTextStyles.body(),
                          decoration: InputDecoration(
                            hintText: 'e.g. Birthday cake (3 tiers)',
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedBorder,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Qty', style: AppTextStyles.inputLabel()),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _customQtyCtrl,
                                    keyboardType: TextInputType.number,
                                    style: AppTextStyles.body(),
                                    decoration: InputDecoration(
                                      border: inputBorder,
                                      enabledBorder: inputBorder,
                                      focusedBorder: focusedBorder,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Price (HTG)',
                                      style: AppTextStyles.inputLabel()),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _customPriceCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true),
                                    style: AppTextStyles.body(),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      prefixText: 'HTG ',
                                      prefixStyle: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.coolGray
                                              : AppColors.darkGray),
                                      border: inputBorder,
                                      enabledBorder: inputBorder,
                                      focusedBorder: focusedBorder,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Line note (optional)', style: AppTextStyles.inputLabel()),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _customNoteCtrl,
                          maxLines: 2,
                          style: AppTextStyles.body(),
                          decoration: InputDecoration(
                            hintText: 'Allergies, plating, timing…',
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedBorder,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Kitchen routing', style: AppTextStyles.inputLabel()),
                        const SizedBox(height: 6),
                        Text(
                          'Food items can be sent to the kitchen from the pre-order list. Drinks stay at the bar.',
                          style: AppTextStyles.caption(color: muted),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Food'),
                              icon: Icon(Icons.restaurant, size: 18),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Drink'),
                              icon: Icon(Icons.local_drink_outlined, size: 18),
                            ),
                          ],
                          selected: {_customIsFood},
                          onSelectionChanged: (s) {
                            if (s.isEmpty) return;
                            setState(() => _customIsFood = s.first);
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _closeCustomItemEditor,
                              child: Text(
                                'Cancel',
                                style: AppTextStyles.button(
                                    color: isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppButton(
                              label: _customEditIndex != null ? 'Save' : 'Add item',
                              icon: _customEditIndex != null ? Icons.save_outlined : Icons.add,
                              fullWidth: false,
                              width: 120,
                              onPressed: _submitCustomItem,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final dividerColor = isDark ? AppColors.darkBackground : const Color(0xFFE8E8EE);
    final borderColor = isDark ? AppColors.darkBackground : const Color(0xFFE0E0E0);
    final readOnly = !_isCreate && !_panelEdit;

    final screenW = MediaQuery.of(context).size.width;
    final drawerW = screenW < 600 ? screenW : 520.0;

    // Live-watch the reservation so the drawer stays in sync if it's updated
    MockDiningReservation? r = widget.reservation;
    if (r != null) {
      try {
        r = ref
            .watch(widget.reservationsProvider)
            .firstWhere((x) => x.id == r!.id);
      } catch (_) {
        r = widget.reservation;
      }
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Container(
            width: drawerW,
            height: double.infinity,
            color: bg,
            child: Column(
              children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              decoration: BoxDecoration(
                color: bg,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isCreate ? 'New reservation' : 'Reservation #${widget.reservation?.id}',
                          style: AppTextStyles.h2(color: textPrimary),
                        ),
                        if (r != null)
                          Text(r.guestName, style: AppTextStyles.caption(color: muted)),
                      ],
                    ),
                  ),
                  if (!_isCreate && r != null) _StatusPill(status: r.status),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.close, color: muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(
                        label: 'Guest details',
                        icon: Icons.person_outline,
                        primary: primary),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _nameCtrl,
                      readOnly: readOnly,
                      label: 'Guest name',
                      required: true,
                      icon: Icons.badge_outlined,
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    _StyledField(
                      controller: _phoneCtrl,
                      readOnly: readOnly,
                      label: 'Telephone',
                      required: true,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      isDark: isDark,
                    ),
                    if (widget.isHotel) ...[
                      const SizedBox(height: AppConstants.spacing8),
                      _HotelRoomPicker(
                        value: _linkedRoomNumber,
                        readOnly: readOnly,
                        isDark: isDark,
                        onChanged: (room) {
                          setState(() {
                            _linkedRoomNumber = room?.number;
                            if (room?.guestName != null) _nameCtrl.text = room!.guestName!;
                            if (room?.guestPhone != null) _phoneCtrl.text = room!.guestPhone!;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _CounterField(
                            label: 'Adults',
                            value: _adults,
                            readOnly: readOnly,
                            onDecrement: _adults > 1 ? () => setState(() => _adults--) : null,
                            onIncrement: () => setState(() => _adults++),
                            isDark: isDark,
                            primary: primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CounterField(
                            label: 'Children',
                            value: _children,
                            readOnly: readOnly,
                            onDecrement:
                                _children > 0 ? () => setState(() => _children--) : null,
                            onIncrement: () => setState(() => _children++),
                            isDark: isDark,
                            primary: primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _PickerButton(
                            icon: Icons.calendar_today_outlined,
                            label: DateFormatter.shortDate(_reservationDate),
                            onTap: readOnly ? null : _pickDate,
                            isDark: isDark,
                            primary: primary,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing8),
                        Expanded(
                          child: _PickerButton(
                            icon: Icons.schedule_outlined,
                            label:
                                '${_reservationTime.hour.toString().padLeft(2, '0')}:${_reservationTime.minute.toString().padLeft(2, '0')}',
                            onTap: readOnly ? null : _pickTime,
                            isDark: isDark,
                            primary: primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    _StyledField(
                      controller: _purposeCtrl,
                      readOnly: readOnly,
                      label: 'Purpose',
                      hint: 'e.g. Birthday, Anniversary…',
                      icon: Icons.celebration_outlined,
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    _StyledField(
                      controller: _notesCtrl,
                      readOnly: readOnly,
                      label: 'Special notes',
                      hint: 'Dietary needs, seating preferences…',
                      icon: Icons.sticky_note_2_outlined,
                      maxLines: 3,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                    Divider(color: dividerColor),
                    const SizedBox(height: 12),

                    // ── Pre-order / catering ──
                    _SectionLabel(
                        label: 'Pre-order / catering',
                        icon: Icons.room_service_outlined,
                        primary: primary),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final canPre = _canEditPreOrder(r);
                        final preItems = _preOrderSource(r);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (canPre || preItems.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: canPre
                                          ? TextButton(
                                              onPressed: () =>
                                                  _showAddPreOrderItemsSheet(
                                                context,
                                                primary,
                                                muted,
                                                isDark,
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: primary,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 6,
                                                ),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize
                                                    .shrinkWrap,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.add_circle_outline,
                                                      size: 18, color: primary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Add items to the order',
                                                    style: AppTextStyles.body(
                                                            color: primary)
                                                        .copyWith(
                                                      fontWeight: FontWeight.w600,
                                                      decoration: TextDecoration
                                                          .underline,
                                                      decorationColor: primary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                  if (preItems.isNotEmpty)
                                    TextButton(
                                      onPressed: _printPreOrder,
                                      style: TextButton.styleFrom(
                                        foregroundColor: primary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.print_outlined,
                                              size: 18, color: primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Print pre-order',
                                            style: AppTextStyles.body(
                                                    color: primary)
                                                .copyWith(
                                              fontWeight: FontWeight.w600,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor: primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppConstants.spacing8),
                            ],
                            if (r != null &&
                                r.status == 'active' &&
                                r.linkedOrderId != null) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AppButton(
                                  label: 'Send food to kitchen',
                                  icon: Icons.soup_kitchen_outlined,
                                  variant: AppButtonVariant.secondary,
                                  fullWidth: false,
                                  onPressed: () => _sendFoodToKitchen(r),
                                ),
                              ),
                              const SizedBox(height: AppConstants.spacing12),
                            ],
                            if (preItems.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text(
                                    'No items pre-ordered yet',
                                    style: AppTextStyles.caption(color: muted),
                                  ),
                                ),
                              )
                            else
                              ReservationPreOrderTable(
                                items: preItems,
                                canEdit: canPre,
                                isDark: isDark,
                                primary: primary,
                                onRemove: (i) {
                                  _mutatePreOrder((list) {
                                    if (i >= 0 && i < list.length) list.removeAt(i);
                                  });
                                },
                                onIncrementQty: (i) {
                                  _mutatePreOrder((list) {
                                    if (i < 0 || i >= list.length) return;
                                    final p = list[i];
                                    if (p.isCustom) {
                                      list[i] = MockDiningReservationPreOrderItem.custom(
                                        p.customItem!.copyWith(
                                            quantity: p.customItem!.quantity + 1),
                                        kitchenSent: p.kitchenSent,
                                      );
                                    } else {
                                      list[i] = MockDiningReservationPreOrderItem.catalog(
                                        p.catalogItem!.copyWith(
                                            quantity: p.catalogItem!.quantity + 1),
                                        kitchenSent: p.kitchenSent,
                                      );
                                    }
                                  });
                                },
                                onDecrementQty: (i) {
                                  _mutatePreOrder((list) {
                                    if (i < 0 || i >= list.length) return;
                                    final p = list[i];
                                    if (p.isCustom) {
                                      if (p.customItem!.quantity <= 1) return;
                                      list[i] = MockDiningReservationPreOrderItem.custom(
                                        p.customItem!.copyWith(
                                            quantity: p.customItem!.quantity - 1),
                                        kitchenSent: p.kitchenSent,
                                      );
                                    } else {
                                      if (p.catalogItem!.quantity <= 1) return;
                                      list[i] = MockDiningReservationPreOrderItem.catalog(
                                        p.catalogItem!.copyWith(
                                            quantity: p.catalogItem!.quantity - 1),
                                        kitchenSent: p.kitchenSent,
                                      );
                                    }
                                  });
                                },
                                onCatalogNoteChanged: (i, note) {
                                  _mutatePreOrder((list) {
                                    if (i < 0 || i >= list.length) return;
                                    final p = list[i];
                                    if (p.catalogItem == null) return;
                                    list[i] = MockDiningReservationPreOrderItem.catalog(
                                      p.catalogItem!.copyWith(note: note),
                                      kitchenSent: p.kitchenSent,
                                    );
                                  });
                                },
                                onCustomNoteChanged: (i, note) {
                                  _mutatePreOrder((list) {
                                    if (i < 0 || i >= list.length) return;
                                    final p = list[i];
                                    if (p.customItem == null) return;
                                    list[i] = MockDiningReservationPreOrderItem.custom(
                                      p.customItem!.copyWith(note: note),
                                      kitchenSent: p.kitchenSent,
                                    );
                                  });
                                },
                                onCustomFoodChanged: (i, isFood) {
                                  _mutatePreOrder((list) {
                                    if (i < 0 || i >= list.length) return;
                                    final p = list[i];
                                    if (p.customItem == null) return;
                                    list[i] = MockDiningReservationPreOrderItem.custom(
                                      p.customItem!.copyWith(isFood: isFood),
                                      kitchenSent: p.kitchenSent,
                                    );
                                  });
                                },
                                onEditCustomPrice: _openCustomItemEditorForEdit,
                                onEditCustom: _openCustomItemEditorForEdit,
                              ),
                            if (preItems.isNotEmpty) ...[
                              const SizedBox(height: AppConstants.spacing8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: primary.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Subtotal',
                                        style: AppTextStyles.caption(color: primary)
                                            .copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        CurrencyFormatter.local(
                                          context,
                                          preItems.fold<double>(
                                            0,
                                            (sum, item) => sum + item.lineTotalHtg,
                                          ),
                                        ),
                                        style: AppTextStyles.body(color: primary).copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    // ── Table assignment ──
                    if (r != null &&
                        (r.status == 'pending' || r.status == 'confirmed')) ...[
                      const SizedBox(height: 20),
                      Divider(color: dividerColor),
                      const SizedBox(height: 12),
                      _SectionLabel(
                          label: 'Table assignment',
                          icon: Icons.table_restaurant,
                          primary: primary),
                      const SizedBox(height: 12),
                      r.assignedTableName != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.deepGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                                border: Border.all(
                                    color: AppColors.deepGreen.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.table_restaurant,
                                      size: 18, color: AppColors.deepGreen),
                                  const SizedBox(width: 10),
                                  Text(r.assignedTableName!,
                                      style: AppTextStyles.body(
                                              color: AppColors.deepGreen)
                                          .copyWith(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkBackground
                                    : AppColors.warmOffWhite,
                                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                                border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : const Color(0xFFE0E0E0)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.table_restaurant, size: 18, color: muted),
                                  const SizedBox(width: 10),
                                  Text('No table assigned yet',
                                      style: AppTextStyles.body(color: muted)),
                                ],
                              ),
                            ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: _buildFooter(r, readOnly),
            ),
          ],
            ),
          ),
          if (_customItemEditorOpen)
            Positioned.fill(
              child: _buildCustomItemOverlay(primary, bg, muted),
            ),
          if (_drawerCancelOverlayOpen)
            Positioned.fill(
              child: _buildDrawerCancelOverlay(muted),
            ),
        ],
      ),
    );
  }

  /// How many footer buttons fit per row (max 3). Uses min cell width so long
  /// labels wrap inside cells rather than forcing one column too early.
  int _drawerFooterColumns(double maxWidth) {
    const minCell = 104.0;
    const gap = 8.0;
    final n = ((maxWidth + gap) / (minCell + gap)).floor();
    return n.clamp(1, 3);
  }

  List<Widget> _footerChunkedRows(List<Widget> cells, int maxPerRow) {
    if (cells.isEmpty) return const [];
    final gap = AppConstants.spacing8;
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += maxPerRow) {
      final end = i + maxPerRow > cells.length ? cells.length : i + maxPerRow;
      final slice = cells.sublist(i, end);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < slice.length; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: slice[j]),
            ],
          ],
        ),
      );
    }
    return rows;
  }

  Widget _buildFooter(MockDiningReservation? r, bool readOnly) {
    const gap = AppConstants.spacing8;

    if (_isCreate) {
      return LayoutBuilder(
        builder: (context, c) {
          final cols = _drawerFooterColumns(c.maxWidth);
          final cancelBtn = AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
            fullWidth: true,
            compact: true,
          );
          final saveBtn = AppButton(
            label: 'Save reservation',
            icon: Icons.check,
            onPressed: _saveCreate,
            fullWidth: true,
            compact: true,
          );
          if (cols >= 2 && c.maxWidth >= 280) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cancelBtn),
                SizedBox(width: gap),
                Expanded(child: saveBtn),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              cancelBtn,
              SizedBox(height: gap),
              saveBtn,
            ],
          );
        },
      );
    }

    if (readOnly) {
      final showConfirm = r?.status == 'pending';
      final showActivate = r != null &&
          (r.status == 'pending' || r.status == 'confirmed');

      return LayoutBuilder(
        builder: (context, c) {
          final cols = _drawerFooterColumns(c.maxWidth);

          final editBtn = AppButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () {
              final r0 = widget.reservation;
              setState(() {
                _panelEdit = true;
                if (r0 != null) {
                  try {
                    final fresh = ref
                        .read(widget.reservationsProvider)
                        .firstWhere((x) => x.id == r0.id);
                    _draftPreOrder = List.from(fresh.preOrderItems);
                  } catch (_) {
                    _draftPreOrder = List.from(r0.preOrderItems);
                  }
                }
              });
            },
            fullWidth: true,
            compact: true,
          );

          final confirmBtn = AppButton(
            label: 'Confirm',
            icon: Icons.check_circle_outline,
            variant: AppButtonVariant.secondary,
            onPressed: () {
              ref.read(widget.reservationsProvider.notifier).confirm(
                    widget.reservation!.id,
                  );
              setState(() {});
            },
            fullWidth: true,
            compact: true,
          );

          final cancelResBtn = AppButton(
            label: 'Cancel reservation',
            icon: Icons.cancel_outlined,
            variant: AppButtonVariant.danger,
            onPressed: _openDrawerCancelOverlay,
            fullWidth: true,
            compact: true,
          );

          final activateBtn = AppButton(
            label: 'Activate & assign table',
            icon: Icons.table_restaurant,
            onPressed: _activate,
            fullWidth: true,
            compact: true,
          );

          final primary = <Widget>[
            editBtn,
            if (showConfirm) confirmBtn,
            cancelResBtn,
          ];

          final primaryRows = _footerChunkedRows(primary, cols);
          final secondaryRows = showActivate
              ? _footerChunkedRows([activateBtn], cols)
              : const <Widget>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...primaryRows.expand((row) => [row, SizedBox(height: gap)]).toList()
                ..removeLast(),
              if (secondaryRows.isNotEmpty) ...[
                SizedBox(height: gap),
                ...secondaryRows,
              ],
            ],
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = _drawerFooterColumns(c.maxWidth);
        final discardBtn = AppButton(
          label: 'Discard',
          variant: AppButtonVariant.ghost,
          onPressed: () => setState(() => _panelEdit = false),
          fullWidth: true,
          compact: true,
        );
        final updateBtn = AppButton(
          label: 'Update',
          icon: Icons.save_outlined,
          onPressed: _saveUpdate,
          fullWidth: true,
          compact: true,
        );
        final rows = _footerChunkedRows([discardBtn, updateBtn], cols);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows
              .expand((row) => [row, SizedBox(height: gap)])
              .toList()
            ..removeLast(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reservation card
// ─────────────────────────────────────────────────────────────────────────────

class _ReservationCard extends StatelessWidget {
  final MockDiningReservation reservation;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onActivate;
  /// When true the content area expands to fill available height so the footer
  /// is always pinned to the bottom — required for equal-height grid rows.
  final bool stretchContent;

  const _ReservationCard({
    required this.reservation,
    required this.isDark,
    required this.onTap,
    required this.onConfirm,
    required this.onCancel,
    required this.onActivate,
    this.stretchContent = false,
  });

  Color get _statusColor {
    switch (reservation.status) {
      case 'confirmed': return AppColors.deepGreen;
      case 'pending':   return AppColors.amber;
      default:          return AppColors.coolGray;
    }
  }

  // Content area (stripe + detail text)
  Widget _buildContentArea(
      BuildContext context, Color primary, Color textPrimary, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Colored left stripe
        Container(
          width: 4,
          decoration: BoxDecoration(
            color: _statusColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppConstants.radiusCard),
              bottomLeft: Radius.circular(AppConstants.radiusCard),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reservation.guestName,
                              style: AppTextStyles.h3(color: textPrimary)),
                          Text(reservation.phone,
                              style: AppTextStyles.caption(color: muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacing8),
                    _StatusPill(status: reservation.status),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 13, color: muted),
                    const SizedBox(width: 5),
                    Text(DateFormatter.shortDate(reservation.reservationAt),
                        style: AppTextStyles.caption(color: muted)),
                    const SizedBox(width: 12),
                    Icon(Icons.schedule_outlined, size: 13, color: muted),
                    const SizedBox(width: 5),
                    Text(DateFormatter.timeOfDay(reservation.reservationAt),
                        style: AppTextStyles.caption(color: muted)),
                    const SizedBox(width: 12),
                    Icon(Icons.people_outlined, size: 13, color: muted),
                    const SizedBox(width: 5),
                    Text('${reservation.partySize} guests',
                        style: AppTextStyles.caption(color: muted)),
                  ],
                ),
                if (reservation.preOrderItems.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.room_service_outlined,
                                size: 11, color: primary),
                            const SizedBox(width: 4),
                            Text(
                              '${reservation.preOrderItems.length} pre-ordered item${reservation.preOrderItems.length > 1 ? 's' : ''}',
                              style: AppTextStyles.caption(color: primary)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 11, color: AppColors.amber),
                            const SizedBox(width: 4),
                            Text(
                              CurrencyFormatter.local(
                                context,
                                reservation.preOrderSubtotalHtg,
                              ),
                              style: AppTextStyles.caption(color: AppColors.amber)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (reservation.purpose != null &&
                    reservation.purpose!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.celebration_outlined, size: 13, color: muted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          reservation.purpose!,
                          style: AppTextStyles.caption(color: muted)
                              .copyWith(fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Footer action row
  Widget _buildFooterRow(Color primary) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBackground : const Color(0xFFF0F0F0),
          ),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppConstants.radiusCard),
          bottomRight: Radius.circular(AppConstants.radiusCard),
        ),
      ),
      child: Row(
        children: [
          _CardAction(
              label: 'View',
              icon: Icons.visibility_outlined,
              color: primary,
              onTap: onTap),
          if (onConfirm != null) ...[
            _VerticalDivider(isDark: isDark),
            _CardAction(
                label: 'Confirm',
                icon: Icons.check_circle_outline,
                color: AppColors.deepGreen,
                onTap: onConfirm!),
          ],
          _VerticalDivider(isDark: isDark),
          _CardAction(
              label: 'Activate',
              icon: Icons.table_restaurant,
              color: AppColors.amber,
              onTap: onActivate),
          _VerticalDivider(isDark: isDark),
          _CardAction(
              label: 'Cancel',
              icon: Icons.cancel_outlined,
              color: AppColors.error,
              onTap: onCancel),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.white;

    // When stretchContent is true (desktop 2-col grid), the content area uses
    // Expanded so the footer is always pinned to the bottom — keeping both
    // cards' footers on the same horizontal line.
    final content = stretchContent
        ? Expanded(child: _buildContentArea(context, primary, textPrimary, muted))
        : _buildContentArea(context, primary, textPrimary, muted);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : Colors.transparent,
          ),
          boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            _buildFooterRow(primary),
          ],
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CardAction({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: AppTextStyles.caption(color: color)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final bool isDark;
  const _VerticalDivider({required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: isDark ? AppColors.darkBackground : const Color(0xFFF0F0F0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color get _color {
    switch (status) {
      case 'confirmed': return AppColors.deepGreen;
      case 'pending':   return AppColors.amber;
      case 'active':    return AppColors.primaryBlue;
      case 'cancelled': return AppColors.error;
      default:          return AppColors.coolGray;
    }
  }

  String get _label {
    switch (status) {
      case 'confirmed': return 'Confirmed';
      case 'pending':   return 'Pending';
      case 'active':    return 'Active';
      case 'cancelled': return 'Cancelled';
      default:          return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(_label,
          style: AppTextStyles.caption(color: _color)
              .copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color primary;
  const _SectionLabel({required this.label, required this.icon, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: primary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: AppTextStyles.caption(color: primary)
              .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 10),
        ),
      ],
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final String label;
  final String? hint;
  final bool required;
  final IconData? icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool isDark;

  const _StyledField({
    required this.controller,
    required this.readOnly,
    required this.label,
    this.hint,
    this.required = false,
    this.icon,
    this.keyboardType,
    this.maxLines = 1,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
    );
    final readonlyBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.5)
              : const Color(0xFFE8E8EE)),
    );
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: AppTextStyles.body(),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, size: 18,
                color: isDark ? AppColors.coolGray : AppColors.darkGray)
            : null,
        border: enabledBorder,
        enabledBorder: readOnly ? readonlyBorder : enabledBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        filled: readOnly,
        fillColor: readOnly
            ? (isDark
                ? AppColors.darkBackground.withValues(alpha: 0.4)
                : AppColors.warmOffWhite)
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _CounterField extends StatelessWidget {
  final String label;
  final int value;
  final bool readOnly;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;
  final bool isDark;
  final Color primary;

  const _CounterField({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onDecrement,
    required this.onIncrement,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption(color: muted)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: readOnly ? null : onDecrement,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: readOnly || onDecrement == null
                        ? (isDark ? AppColors.darkSurface : const Color(0xFFEEEEEE))
                        : primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.remove, size: 16,
                      color: readOnly || onDecrement == null
                          ? (isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC))
                          : primary),
                ),
              ),
              Text('$value',
                  style: AppTextStyles.h2(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
              GestureDetector(
                onTap: readOnly ? null : onIncrement,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: readOnly
                        ? (isDark ? AppColors.darkSurface : const Color(0xFFEEEEEE))
                        : primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.add, size: 16,
                      color: readOnly
                          ? (isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC))
                          : primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDark;
  final Color primary;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final textColor = disabled
        ? (isDark ? AppColors.coolGray : AppColors.darkGray)
        : (isDark ? AppColors.warmWhite : AppColors.nearBlack);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: AppConstants.buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: disabled
              ? (isDark
                  ? AppColors.darkBackground.withValues(alpha: 0.4)
                  : AppColors.warmOffWhite)
              : null,
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          border: Border.all(
            color: disabled
                ? (isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.5)
                    : const Color(0xFFE8E8EE))
                : (isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18,
                color: disabled
                    ? (isDark ? AppColors.coolGray : const Color(0xFFCCCCCC))
                    : primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: AppTextStyles.body(color: textColor),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chip
// ─────────────────────────────────────────────────────────────────────────────

class _ResFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ResFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary : primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
          border: Border.all(
            color: selected ? primary : primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? AppColors.white : primary),
            const SizedBox(width: 5),
            Text(label,
                style: AppTextStyles.caption(
                  color: selected ? AppColors.white : primary,
                ).copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hotel room picker
// ─────────────────────────────────────────────────────────────────────────────

class _HotelRoomPicker extends ConsumerWidget {
  const _HotelRoomPicker({
    required this.value,
    required this.readOnly,
    required this.isDark,
    required this.onChanged,
  });

  final String? value;
  final bool readOnly;
  final bool isDark;
  final void Function(MockRoom?) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref
        .watch(mockRoomsProvider)
        .where((r) => r.status == 'occupied' || r.status == 'checkout_today')
        .toList();
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
      borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
    );
    return DropdownButtonFormField<String?>(
      initialValue: value,
      style: AppTextStyles.body(),
      decoration: InputDecoration(
        labelText: 'Link to room (optional)',
        prefixIcon: Icon(Icons.hotel_outlined, size: 18,
            color: isDark ? AppColors.coolGray : AppColors.darkGray),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        for (final r in rooms)
          DropdownMenuItem<String?>(
            value: r.number,
            child: Text('Room ${r.number} — ${r.guestName ?? "Guest"}'),
          ),
      ],
      onChanged: readOnly
          ? null
          : (v) {
              if (v == null) { onChanged(null); return; }
              onChanged(rooms.firstWhere((x) => x.number == v));
            },
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/providers/app_notification_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/payment_link_dialog.dart';
import '../../core/widgets/status_badge.dart';
import '../models/retail_cart_entry.dart';
import 'checkout_wizard.dart';
import 'pos_screen.dart';

const int _kPageSize = 10;

// ──────────────────────────────────────────────────────────────────────────────
// Main screen
// ──────────────────────────────────────────────────────────────────────────────

class QuotesScreen extends ConsumerStatefulWidget {
  const QuotesScreen({super.key});

  @override
  ConsumerState<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends ConsumerState<QuotesScreen> {
  MockRetailQuote? _selectedQuote;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 0;
  /// 0 = Active (draft), 1 = Inactive (expired / cancelled only; converted → order).
  int _quotesTab = 0;

  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MockRetailQuote> get _filtered {
    final all = ref.watch(quotesProvider);
    return (all.where((q) {
      final inTab = _quotesTab == 0
          ? q.status.isActiveQuotesTab
          : q.status.isInactiveQuotesTab;
      if (!inTab) return false;
      if (_startDate != null) {
        final s = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (q.createdAt.isBefore(s)) return false;
      }
      if (_endDate != null) {
        final e = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (q.createdAt.isAfter(e)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchNum = q.quoteNumber.toLowerCase().contains(query);
        final matchClient = q.clientName?.toLowerCase().contains(query) ?? false;
        if (!matchNum && !matchClient) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  List<MockRetailQuote> get _paginated {
    final f = _filtered;
    final start = _currentPage * _kPageSize;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _kPageSize).clamp(0, f.length));
  }

  int get _totalPages {
    final n = _filtered.length;
    if (n == 0) return 1;
    return ((n - 1) ~/ _kPageSize) + 1;
  }

  void _resetPage() => setState(() => _currentPage = 0);

  void _onTapQuote(MockRetailQuote quote, bool isMobile) {
    if (isMobile) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _QuoteDetailPage(quoteId: quote.id),
      ));
    } else {
      setState(() => _selectedQuote = quote);
    }
  }

  Future<void> _pickDate(bool isStart) async {
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
      _resetPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(quotesProvider); // rebuild on data changes
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If selected quote was deleted/changed, keep ref but re-read from provider
    if (_selectedQuote != null) {
      final updated = ref
          .read(quotesProvider)
          .where((q) => q.id == _selectedQuote!.id)
          .firstOrNull;
      if (updated != null && updated != _selectedQuote) {
        _selectedQuote = updated;
      }
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile =
          constraints.maxWidth < AppConstants.mobileBreakpoint;
      /// One toolbar row (tabs left; From/To + search right) for any non-mobile width.
      final useSingleToolbarRow = !isMobile;
      final listPanel =
          _buildListPanel(isDark, isMobile, useSingleToolbarRow);

      return Stack(
        children: [
          listPanel,
          if (_selectedQuote != null && !isMobile)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedQuote = null),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.20),
                      ),
                    ),
                  ),
                  Container(
                    width: AppConstants.retailDetailSidePanelWidth(
                        constraints.maxWidth),
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
                    child: _QuoteDetailPanel(
                      quoteId: _selectedQuote!.id,
                      isDark: isDark,
                      onClose: () =>
                          setState(() => _selectedQuote = null),
                      onQuoteUpdated: () => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _buildListPanel(
      bool isDark, bool isMobile, bool useSingleToolbarRow) {
    final filtered = _filtered;
    final quotes = _paginated;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacing24,
              AppConstants.spacing24,
              AppConstants.spacing24,
              0,
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Devis',
                              style: AppTextStyles.h1(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.primaryBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          AppButton(
                            label: 'Nouveau devis',
                            onPressed: () => context.push(
                              AppRoutes.retailPos,
                              extra: const RetailPosRouteArgs(quoteMode: true),
                            ),
                            icon: Icons.add_rounded,
                            compact: true,
                            fullWidth: false,
                          ),
                        ],
                      ),
                      if (_totalPages > 1) ...[
                        const SizedBox(height: AppConstants.spacing8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _buildPagination(isDark, filtered.length),
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'Devis',
                          style: AppTextStyles.h1(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.primaryBlue,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_totalPages > 1) ...[
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: _buildPagination(isDark, filtered.length),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing12),
                      ],
                      AppButton(
                        label: 'Nouveau devis',
                        onPressed: () => context.push(
                          AppRoutes.retailPos,
                          extra: const RetailPosRouteArgs(quoteMode: true),
                        ),
                        icon: Icons.add_rounded,
                        compact: true,
                        fullWidth: false,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppConstants.spacing16),

          // ── Tabs + filters + search (desktop: one row); mobile/tablet: stacked ─
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24),
            child: useSingleToolbarRow
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildQuotesTabToggle(isDark, dense: true),
                      const SizedBox(width: AppConstants.spacing12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _buildFilters(
                            isDark,
                            dense: true,
                            desktopToolbarEnd: true,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFilters(
                        isDark,
                        dense: true,
                        desktopToolbarEnd: false,
                      ),
                      const SizedBox(height: AppConstants.spacing12),
                      _buildQuotesTabToggle(isDark, dense: true),
                    ],
                  ),
          ),
          const SizedBox(height: AppConstants.spacing8),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24),
            child: Text(
              _quotesTab == 0
                  ? '${filtered.length} devis actif${filtered.length == 1 ? '' : 's'}'
                  : '${filtered.length} devis inactif${filtered.length == 1 ? '' : 's'}',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacing8),

          // ── Quote list ───────────────────────────────────────────────────
          Expanded(
            child: quotes.isEmpty
                ? EmptyState(
                    icon: Icons.request_quote_outlined,
                    title: filtered.isEmpty &&
                            _searchQuery.isEmpty &&
                            _startDate == null &&
                            _endDate == null
                        ? (_quotesTab == 0
                            ? 'Aucun devis en cours'
                            : 'Aucun devis inactif')
                        : 'Aucun résultat',
                    message: filtered.isEmpty &&
                            _searchQuery.isEmpty &&
                            _startDate == null &&
                            _endDate == null
                        ? (_quotesTab == 0
                            ? 'Créez un devis depuis la caisse ou touchez Nouveau devis.'
                            : 'Les devis expirés et annulés apparaissent ici.')
                        : 'Modifiez la recherche ou les filtres de date.',
                    actionLabel: 'Nouveau devis',
                    onAction: () => context.push(
                          AppRoutes.retailPos,
                          extra: const RetailPosRouteArgs(quoteMode: true),
                        ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacing24,
                      AppConstants.spacing4,
                      AppConstants.spacing24,
                      AppConstants.spacing16,
                    ),
                    itemCount: quotes.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppConstants.spacing8),
                    itemBuilder: (_, i) {
                      final q = quotes[i];
                      return _QuoteCard(
                        quote: q,
                        isSelected: _selectedQuote?.id == q.id,
                        onTap: () => _onTapQuote(q, isMobile),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotesTabToggle(bool isDark, {bool dense = false}) {
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
            _QuotesToggleTab(
              icon: Icons.edit_note_outlined,
              label: 'Devis en cours',
              badge: _QuotesTabCountBadge(isDark: isDark, activeTab: true),
              isSelected: _quotesTab == 0,
              isDark: isDark,
              isLeft: true,
              dense: dense,
              onTap: () => _setQuotesTab(0),
            ),
            Container(width: 1, color: borderColor),
            _QuotesToggleTab(
              icon: Icons.inventory_2_outlined,
              label: 'Devis inactifs',
              badge: _QuotesTabCountBadge(isDark: isDark, activeTab: false),
              isSelected: _quotesTab == 1,
              isDark: isDark,
              isLeft: false,
              dense: dense,
              onTap: () => _setQuotesTab(1),
            ),
          ],
        ),
      ),
    );
  }

  void _setQuotesTab(int tab) {
    if (tab == _quotesTab) return;
    setState(() {
      _quotesTab = tab;
      _currentPage = 0;
      _selectedQuote = null;
    });
  }

  Widget _buildFilters(
    bool isDark, {
    required bool dense,
    required bool desktopToolbarEnd,
  }) {
    final fromChip = _DateChip(
      label: _startDate == null ? 'De' : _formatDate(_startDate!),
      icon: Icons.calendar_today_outlined,
      active: _startDate != null,
      isDark: isDark,
      dense: dense,
      onTap: () => _pickDate(true),
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
      onTap: () => _pickDate(false),
      onClear: _endDate != null
          ? () => setState(() {
                _endDate = null;
                _resetPage();
              })
          : null,
    );

    final searchField = _PillSearchField(
      controller: _searchCtrl,
      hintText: 'Devis n° ou client…',
      width: dense ? 188 : 210,
      isDark: isDark,
      dense: dense,
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

    if (desktopToolbarEnd) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [fromChip, toChip, searchField],
      );
    }

    return LayoutBuilder(builder: (_, constraints) {
      if (constraints.maxWidth >= AppConstants.mobileBreakpoint) {
        return Row(
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [fromChip, toChip],
            ),
            const Spacer(),
            searchField,
          ],
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [searchField, fromChip, toChip],
      );
    });
  }

  Widget _buildPagination(bool isDark, int total) {
    final start = _currentPage * _kPageSize + 1;
    final end = ((_currentPage + 1) * _kPageSize).clamp(0, total);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$start–$end sur $total',
          style: AppTextStyles.caption(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
        const SizedBox(width: AppConstants.spacing12),
        _PaginationBtn(
          icon: Icons.chevron_left,
          enabled: _currentPage > 0,
          isDark: isDark,
          onTap: () => setState(() => _currentPage--),
        ),
        const SizedBox(width: AppConstants.spacing4),
        ...List.generate(_totalPages, (i) {
          final isActive = i == _currentPage;
          final showChip = _totalPages <= 7 ||
              i == 0 ||
              i == _totalPages - 1 ||
              (i - _currentPage).abs() <= 1;
          if (!showChip) {
            if (i == 1 || i == _totalPages - 2) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '…',
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => setState(() => _currentPage = i),
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: AppConstants.animFast,
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
                        : (isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray),
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          );
        }),
        const SizedBox(width: AppConstants.spacing4),
        _PaginationBtn(
          icon: Icons.chevron_right,
          enabled: _currentPage < _totalPages - 1,
          isDark: isDark,
          onTap: () => setState(() => _currentPage++),
        ),
      ],
    );
  }
}

// ── Quotes Active / Inactive segmented control ────────────────────────────────

class _QuotesToggleTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? badge;
  final bool isSelected;
  final bool isDark;
  final bool isLeft;
  final bool dense;
  final VoidCallback onTap;

  const _QuotesToggleTab({
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

class _QuotesTabCountBadge extends ConsumerWidget {
  final bool isDark;
  final bool activeTab;

  const _QuotesTabCountBadge({
    required this.isDark,
    required this.activeTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(quotesProvider.select((list) => list
        .where((q) => activeTab
            ? q.status.isActiveQuotesTab
            : q.status.isInactiveQuotesTab)
        .length));
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

// ──────────────────────────────────────────────────────────────────────────────
// Quote card
// ──────────────────────────────────────────────────────────────────────────────

class _QuoteCard extends StatelessWidget {
  final MockRetailQuote quote;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuoteCard({
    required this.quote,
    required this.isSelected,
    required this.onTap,
  });

  StatusType get _statusType {
    switch (quote.status) {
      case MockRetailQuoteStatus.draft:
        return StatusType.pending;
      case MockRetailQuoteStatus.converted:
        return StatusType.done;
      case MockRetailQuoteStatus.expired:
        return StatusType.inactive;
      case MockRetailQuoteStatus.cancelled:
        return StatusType.occupied;
    }
  }

  String get _statusLabel {
    switch (quote.status) {
      case MockRetailQuoteStatus.draft:
        return 'Brouillon';
      case MockRetailQuoteStatus.converted:
        return 'Converted';
      case MockRetailQuoteStatus.expired:
        return 'Expiré';
      case MockRetailQuoteStatus.cancelled:
        return 'Annulé';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clientLabel = quote.clientName?.isNotEmpty == true
        ? quote.clientName!
        : 'Client de passage';
    final total = quote.totalBeforeTaxHtg();

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
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlue.withValues(alpha: 0.6)
                  : (isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFE8E8E8)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow:
                isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
              vertical: AppConstants.spacing8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Quote # · client | date · lines + fulfillment
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            flex: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    quote.quoteNumber,
                                    style: AppTextStyles.body(
                                      color: isDark
                                          ? AppColors.skyBlue
                                          : AppColors.primaryBlue,
                                    ).copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (quote.paymentLinkSent) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.deepGreen
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.link,
                                            size: 9,
                                            color: isDark
                                                ? AppColors.mediumGreen
                                                : AppColors.deepGreen),
                                        const SizedBox(width: 2),
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
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 5),
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
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_formatDate(quote.createdAt)} · '
                              '${quote.lines.length} ligne${quote.lines.length == 1 ? '' : 's'}',
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray,
                              ).copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _FulfillmentChip(mode: quote.fulfillmentMode),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacing8),
                // Amount + status + chevron (single row)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      CurrencyFormatter.local(context, total),
                      style: AppTextStyles.body(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack,
                      ).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    StatusBadge(
                      status: _statusType,
                      customLabel: _statusLabel,
                      compact: true,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Active quote: share / print (same UX as active retail orders)
// ──────────────────────────────────────────────────────────────────────────────

void _showActiveQuoteWhatsAppDialog(
    BuildContext context, WidgetRef ref, MockRetailQuote quote) {
  final ctrl = TextEditingController(text: quote.clientPhone?.trim() ?? '');
  final errHolder = <String?>[null];
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Envoyer par WhatsApp'),
          content: TextField(
            controller: ctrl,
            onChanged: (_) => setD(() => errHolder[0] = null),
            decoration: InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: '+509 XXXX-XXXX',
              prefixIcon: const Icon(Icons.phone_outlined),
              errorText: errHolder[0],
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusInput),
              ),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: InputFormatters.phone,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setD(() => errHolder[0] = 'Veuillez saisir un numéro de téléphone.');
                  return;
                }
                Navigator.pop(ctx);
                ref.read(appNotificationProvider.notifier).show(
                      'Résumé du devis envoyé par WhatsApp',
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

void _showActiveQuoteEmailDialog(
    BuildContext context, WidgetRef ref, MockRetailQuote quote) {
  final ctrl = TextEditingController(text: quote.clientEmail?.trim() ?? '');
  final errHolder = <String?>[null];
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Envoyer le devis par e-mail'),
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
                    BorderRadius.circular(AppConstants.radiusInput),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            inputFormatters: InputFormatters.email,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final email = ctrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  setD(() =>
                      errHolder[0] = 'Veuillez saisir une adresse e-mail valide.');
                  return;
                }
                Navigator.pop(ctx);
                ref.read(appNotificationProvider.notifier).show(
                      'Résumé du devis envoyé par e-mail',
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

void _showActiveQuotePrintDialog(BuildContext context, MockRetailQuote quote) {
  final name = quote.clientName?.trim();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Imprimer'),
      content: Text(
        name == null || name.isEmpty
            ? 'Devis ${quote.quoteNumber} envoyé à l\'imprimante.'
            : 'Devis ${quote.quoteNumber} pour $name envoyé à l\'imprimante.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Quote detail panel (right panel / overlay)
// ──────────────────────────────────────────────────────────────────────────────

class _QuoteDetailPanel extends ConsumerStatefulWidget {
  final String quoteId;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onQuoteUpdated;

  /// When false, WhatsApp / email / print appear only in the parent [AppBar] (mobile).
  final bool showInlineShareActions;

  const _QuoteDetailPanel({
    required this.quoteId,
    required this.isDark,
    required this.onClose,
    required this.onQuoteUpdated,
    this.showInlineShareActions = true,
  });

  @override
  ConsumerState<_QuoteDetailPanel> createState() => _QuoteDetailPanelState();
}

class _QuoteDetailPanelState extends ConsumerState<_QuoteDetailPanel> {
  bool _sendingLink = false;

  MockRetailQuote? get _quote => ref
      .watch(quotesProvider)
      .where((q) => q.id == widget.quoteId)
      .firstOrNull;

  Future<void> _sendPaymentLink(MockRetailQuote quote) async {
    final result = await showDialog<PaymentLinkSendResult>(
      context: context,
      builder: (ctx) => PaymentLinkDialog(
        referenceLabel: quote.quoteNumber,
        description: "Partagez une page de paiement Stripe. Saisissez le contact du payeur ; "
            'le devis devient une commande active une fois payé.',
        isDark: widget.isDark,
      ),
    );

    if (result != null && mounted) {
      setState(() => _sendingLink = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      ref.read(quotesProvider.notifier).markPaymentLinkSent(quote.id);
      setState(() => _sendingLink = false);
      widget.onQuoteUpdated();
      if (!mounted) return;
      final channelName = result.channel == PaymentLinkChannel.whatsApp
          ? 'WhatsApp'
          : result.channel == PaymentLinkChannel.email
              ? 'E-mail'
              : 'SMS';
      final path = buildQuotePaymentLinkPath(quote.quoteNumber);
      await showPaymentLinkSuccessDialog(
        context,
        isDark: widget.isDark,
        title: 'Lien de paiement pour ${quote.quoteNumber} — envoyé via $channelName',
        pathOrUrl: path,
        subtitle: 'Le lien est actif. Copiez-le ou partagez-le avec votre client.',
      );
    }
  }

  void _editQuote(MockRetailQuote quote) {
    context.push(
      AppRoutes.retailPos,
      extra: RetailPosRouteArgs(quoteMode: true, quoteToEdit: quote),
    );
  }

  void _convertToOrder(MockRetailQuote quote) {
    final cart = quote.lines
        .map((l) => RetailCartEntry(product: l.product, quantity: l.quantity))
        .toList();
    showRetailCheckoutDialog(
      context,
      ref,
      cart: cart,
      discountPercent: quote.discountPercent,
      isQuote: false,
      existingQuote: quote,
      initialStepIndex: 2,
      onSuccess: () {
        widget.onQuoteUpdated();
      },
    );
  }

  Future<void> _confirmExpireQuote(MockRetailQuote quote) async {
    final isDark = widget.isDark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        title: Text(
          'Marquer comme expiré ?',
          style: AppTextStyles.h3(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        ),
        content: Text(
          'Cela marquera ${quote.quoteNumber} comme expiré. '
          'Vous pourrez encore le consulter, mais plus envoyer de lien.',
          style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Marquer expiré',
              style: AppTextStyles.button(color: AppColors.boldRed),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(quotesProvider.notifier).expire(quote.id);
      widget.onQuoteUpdated();
    }
  }

  Future<void> _confirmCancelQuote(MockRetailQuote quote) async {
    final isDark = widget.isDark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        title: Text(
          'Annuler ce devis ?',
          style: AppTextStyles.h3(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        ),
        content: Text(
          '${quote.quoteNumber} passera dans les devis inactifs comme annulé. '
          'Cette action est définitive.',
          style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Garder le devis'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Annuler le devis',
              style: AppTextStyles.button(color: AppColors.boldRed),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(quotesProvider.notifier).cancel(quote.id);
      widget.onQuoteUpdated();
    }
  }

  Future<void> _confirmReactivateQuote(MockRetailQuote quote) async {
    final isDark = widget.isDark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        title: Text(
          'Réactiver le devis ?',
          style: AppTextStyles.h3(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        ),
        content: Text(
          '${quote.quoteNumber} redeviendra un brouillon dans les devis en cours. '
          'Vous pourrez le modifier, envoyer un lien ou le convertir en commande.',
          style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Pas maintenant'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réactiver'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(quotesProvider.notifier).reactivateToDraft(quote.id);
      widget.onQuoteUpdated();
      if (!mounted) return;
      ref.read(appNotificationProvider.notifier).show(
            '${quote.quoteNumber} est de nouveau un brouillon.',
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    if (quote == null) {
      return Container(
        color: widget.isDark ? AppColors.darkSurface : AppColors.white,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.request_quote_outlined,
                  size: 40,
                  color: widget.isDark
                      ? AppColors.coolGray
                      : AppColors.darkGray),
              const SizedBox(height: 12),
              Text('Devis introuvable',
                  style: AppTextStyles.body(
                      color: widget.isDark
                          ? AppColors.coolGray
                          : AppColors.darkGray)),
            ],
          ),
        ),
      );
    }

    final isDark = widget.isDark;
    final total = quote.totalBeforeTaxHtg();
    final isDraft = quote.status == MockRetailQuoteStatus.draft;

    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacing16,
              AppConstants.spacing12,
              AppConstants.spacing8,
              AppConstants.spacing12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppConstants.spacing8,
                        runSpacing: 4,
                        children: [
                          Text(
                            quote.quoteNumber,
                            style: AppTextStyles.h2(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ),
                          ),
                          if (isDraft)
                            Material(
                              color: isDark
                                  ? AppColors.skyBlue.withValues(alpha: 0.22)
                                  : AppColors.lightBlue,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusButton,
                              ),
                              child: InkWell(
                                onTap: () => _editQuote(quote),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Modifier le devis',
                                    style: AppTextStyles.caption(
                                      color: isDark
                                          ? AppColors.amber
                                          : AppColors.nearBlack,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      _statusRowFor(quote, isDark),
                    ],
                  ),
                ),
                if (isDraft && widget.showInlineShareActions) ...[
                  IconButton(
                    onPressed: () =>
                        _showActiveQuoteWhatsAppDialog(context, ref, quote),
                    icon: Icon(
                      Icons.send_outlined,
                      size: 18,
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                    tooltip: 'Partager par WhatsApp',
                    style:
                        IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                  IconButton(
                    onPressed: () =>
                        _showActiveQuoteEmailDialog(context, ref, quote),
                    icon: Icon(
                      Icons.email_outlined,
                      size: 18,
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                    tooltip: 'Envoyer par e-mail',
                    style:
                        IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                  IconButton(
                    onPressed: () =>
                        _showActiveQuotePrintDialog(context, quote),
                    icon: Icon(
                      Icons.print_outlined,
                      size: 18,
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                    tooltip: 'Imprimer',
                    style:
                        IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                  ),
                ],
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 20,
                      color: isDark ? AppColors.coolGray : AppColors.darkGray),
                  onPressed: widget.onClose,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE),
          ),

          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Client
                  _DetailSection(
                    label: 'Client',
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(
                          icon: Icons.person_outline_rounded,
                          text: quote.clientName?.isNotEmpty == true
                              ? quote.clientName!
                              : 'Client de passage',
                          isDark: isDark,
                          bold: true,
                        ),
                        if (quote.clientPhone?.isNotEmpty ?? false)
                          _DetailRow(
                            icon: Icons.phone_outlined,
                            text: quote.clientPhone!,
                            isDark: isDark,
                          ),
                        if (quote.clientEmail?.isNotEmpty ?? false)
                          _DetailRow(
                            icon: Icons.email_outlined,
                            text: quote.clientEmail!,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing12),

                  // Fulfillment
                  _DetailSection(
                    label: 'Remise',
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _FulfillmentChip(mode: quote.fulfillmentMode),
                          ],
                        ),
                        if (quote.deliveryLocation?.isNotEmpty ?? false)
                          _DetailRow(
                            icon: Icons.place_outlined,
                            text: quote.deliveryLocation!,
                            isDark: isDark,
                          ),
                        if (quote.deliveryPhone?.isNotEmpty ?? false)
                          _DetailRow(
                            icon: Icons.phone_outlined,
                            text: quote.deliveryPhone!,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing12),

                  // Items
                  _DetailSection(
                    label: 'Articles',
                    isDark: isDark,
                    child: _LinesTable(
                      rows: quote.lines
                          .map((l) => (
                                l.quantity,
                                l.product.name,
                                l.unitPriceHtg,
                                l.lineTotalHtg,
                              ))
                          .toList(),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing8),

                  // Totals
                  Divider(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFEEEEEE),
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  _TotalRow(
                    label: 'Sous-total',
                    amount: quote.subtotalHtg(),
                    isDark: isDark,
                    context: context,
                  ),
                  if (quote.discountPercent > 0) ...[
                    const SizedBox(height: 4),
                    _TotalRow(
                      label:
                          'Remise (${quote.discountPercent.toStringAsFixed(0)} %)',
                      amount: -quote.discountAmountHtg(),
                      isDark: isDark,
                      context: context,
                      isDiscount: true,
                    ),
                  ],
                  const SizedBox(height: 4),
                  _TotalRow(
                    label: 'Total',
                    amount: total,
                    isDark: isDark,
                    context: context,
                    isBold: true,
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  // Created date
                  Text(
                    'Créé le ${_formatDateLong(quote.createdAt)}',
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Actions (2 compact buttons per row, draft only) ───────────────
          if (isDraft) ...[
            Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _convertToOrder(quote),
                          icon: const Icon(Icons.payment_rounded, size: 14),
                          label: Text(
                            'Payer et convertir',
                            style: AppTextStyles.button(
                              color: AppColors.nearBlack,
                            ).copyWith(fontSize: 12),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.amber,
                            foregroundColor: AppColors.nearBlack,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                          ),
                        ),
                      ),
                      if (!quote.isPaid) ...[
                        const SizedBox(width: AppConstants.spacing8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _sendingLink
                                ? null
                                : () => _sendPaymentLink(quote),
                            icon: _sendingLink
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(
                                    quote.paymentLinkSent
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.link_rounded,
                                    size: 14,
                                    color: isDark
                                        ? AppColors.mediumGreen
                                        : AppColors.deepGreen,
                                  ),
                            label: Text(
                              quote.paymentLinkSent
                                  ? 'Renvoyer le lien'
                                  : 'Envoyer le lien',
                              style: AppTextStyles.button(
                                color: isDark
                                    ? AppColors.mediumGreen
                                    : AppColors.deepGreen,
                              ).copyWith(fontSize: 12),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.mediumGreen
                                  : AppColors.deepGreen,
                              side: BorderSide(
                                  color: isDark
                                      ? AppColors.mediumGreen
                                      : AppColors.deepGreen),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusButton),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmExpireQuote(quote),
                          icon: Icon(Icons.event_busy_outlined,
                              size: 14,
                              color: isDark
                                  ? AppColors.coralRed
                                  : AppColors.boldRed),
                          label: Text(
                            'Marquer expiré',
                            style: AppTextStyles.button(
                              color: isDark
                                  ? AppColors.coralRed
                                  : AppColors.boldRed,
                            ).copyWith(fontSize: 12),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? AppColors.coralRed
                                : AppColors.boldRed,
                            side: BorderSide(
                                color: isDark
                                    ? AppColors.coralRed
                                    : AppColors.boldRed),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmCancelQuote(quote),
                          icon: Icon(Icons.cancel_outlined,
                              size: 14,
                              color: isDark
                                  ? AppColors.coralRed
                                  : AppColors.boldRed),
                          label: Text(
                            'Annuler le devis',
                            style: AppTextStyles.button(
                              color: isDark
                                  ? AppColors.coralRed
                                  : AppColors.boldRed,
                            ).copyWith(fontSize: 12),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? AppColors.coralRed
                                : AppColors.boldRed,
                            side: BorderSide(
                                color: isDark
                                    ? AppColors.coralRed
                                    : AppColors.boldRed),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // ── Inactive: reactivate back to draft ───────────────────────────
          if (!isDraft && quote.status.canReactivateToDraft) ...[
            Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing12),
              child: ElevatedButton.icon(
                onPressed: () => _confirmReactivateQuote(quote),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text(
                  'Réactiver le devis',
                  style: AppTextStyles.button(color: AppColors.nearBlack)
                      .copyWith(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.nearBlack,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing16, vertical: 12),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusRowFor(MockRetailQuote quote, bool isDark) {
    final (badgeStatus, badgeLabel) = switch (quote.status) {
      MockRetailQuoteStatus.draft => (StatusType.pending, 'Brouillon'),
      MockRetailQuoteStatus.converted => (StatusType.done, 'Converted'),
      MockRetailQuoteStatus.expired => (StatusType.inactive, 'Expiré'),
      MockRetailQuoteStatus.cancelled => (StatusType.occupied, 'Annulé'),
    };
    return Row(
      children: [
        StatusBadge(
          status: badgeStatus,
          customLabel: badgeLabel,
          compact: true,
        ),
        const SizedBox(width: AppConstants.spacing8),
        Text(
          _formatDate(quote.createdAt),
          style: AppTextStyles.caption(
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Mobile full-screen detail page
// ──────────────────────────────────────────────────────────────────────────────

class _QuoteDetailPage extends ConsumerWidget {
  final String quoteId;

  const _QuoteDetailPage({required this.quoteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quote = ref
        .watch(quotesProvider)
        .where((q) => q.id == quoteId)
        .firstOrNull;
    final isDraft = quote?.status == MockRetailQuoteStatus.draft;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      appBar: AppBar(
        title: Text(
          'Détails du devis',
          style: AppTextStyles.h3(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (isDraft && quote != null) ...[
            IconButton(
              icon: const Icon(Icons.send_outlined, size: 22),
              tooltip: 'Partager par WhatsApp',
              onPressed: () =>
                  _showActiveQuoteWhatsAppDialog(context, ref, quote),
            ),
            IconButton(
              icon: const Icon(Icons.email_outlined, size: 22),
              tooltip: 'Envoyer par e-mail',
              onPressed: () => _showActiveQuoteEmailDialog(context, ref, quote),
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined, size: 22),
              tooltip: 'Imprimer',
              onPressed: () => _showActiveQuotePrintDialog(context, quote),
            ),
          ],
        ],
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: _QuoteDetailPanel(
        quoteId: quoteId,
        isDark: isDark,
        onClose: () => Navigator.of(context).pop(),
        onQuoteUpdated: () {},
        showInlineShareActions: false,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small helper widgets
// ──────────────────────────────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String label;
  final bool isDark;
  final Widget child;

  const _DetailSection({
    required this.label,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.caption(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppConstants.spacing8),
        child,
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;
  final bool bold;

  const _DetailRow({
    required this.icon,
    required this.text,
    required this.isDark,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing4),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
          const SizedBox(width: AppConstants.spacing8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isDark;
  final BuildContext context;
  final bool isBold;
  final bool isDiscount;

  const _TotalRow({
    required this.label,
    required this.amount,
    required this.isDark,
    required this.context,
    this.isBold = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext buildContext) {
    final baseColor = isDiscount
        ? (isDark ? AppColors.mediumGreen : AppColors.deepGreen)
        : (isDark ? AppColors.warmWhite : AppColors.nearBlack);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTextStyles.body(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ).copyWith(
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal)),
        Text(
          isDiscount
              ? '- ${CurrencyFormatter.local(context, amount.abs())}'
              : CurrencyFormatter.local(context, amount),
          style: (isBold ? AppTextStyles.price() : AppTextStyles.body())
              .copyWith(
            color: baseColor,
            fontSize: isBold ? 15 : 13,
          ),
        ),
      ],
    );
  }
}

class _FulfillmentChip extends StatelessWidget {
  final RetailFulfillmentMode mode;

  const _FulfillmentChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        Text(
          label,
          style:
              AppTextStyles.caption(color: color).copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}

class _PaginationBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;

  const _PaginationBtn({
    required this.icon,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? (isDark ? AppColors.warmWhite : AppColors.nearBlack)
              : (isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD)),
        ),
      ),
    );
  }
}

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
          vertical: dense ? 5 : 7,
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
              size: dense ? 13 : 14,
              color: active
                  ? AppColors.primaryBlue
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(width: 5),
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
                  size: 12,
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

// ── Lines table ───────────────────────────────────────────────────────────────

/// Compact POS-style table: Qty | Item | Unit | Total
/// Each [rows] entry is (qty, name, unitPriceHtg, lineTotalHtg).
class _LinesTable extends StatelessWidget {
  final List<(int, String, double, double)> rows;
  final bool isDark;

  const _LinesTable({required this.rows, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hdrBg = isDark ? AppColors.darkBackground : const Color(0xFFEEF2F7);
    final rowBg =
        isDark ? AppColors.darkSurface.withValues(alpha: 0.6) : AppColors.white;
    final divColor = isDark ? AppColors.darkBorder : const Color(0xFFE4E8EE);
    final hdrColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final valColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;

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
          child: Row(children: [
            SizedBox(
                width: 28,
                child: Text('Qté', style: hdr(), textAlign: TextAlign.center)),
            const SizedBox(width: 8),
            Expanded(child: Text('Article', style: hdr())),
            SizedBox(
                width: 70,
                child: Text('Unité', style: hdr(), textAlign: TextAlign.right)),
            const SizedBox(width: 6),
            SizedBox(
                width: 70,
                child:
                    Text('Total', style: hdr(), textAlign: TextAlign.right)),
          ]),
        );

    Widget dataRow(int qty, String name, double unit, double total,
            {bool last = false}) =>
        Container(
          color: rowBg,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                              fontSize: 11),
                          textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(name,
                          style: val(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)),
                  SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(unit),
                          style: val(), textAlign: TextAlign.right)),
                  const SizedBox(width: 6),
                  SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(total),
                          style: val(bold: true), textAlign: TextAlign.right)),
                ],
              ),
            ),
            if (!last)
              Container(
                  height: 0.5,
                  color: divColor,
                  margin: const EdgeInsets.symmetric(horizontal: 10)),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: divColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        headerRow(),
        Container(height: 1, color: divColor),
        ...rows.asMap().entries.map((e) => dataRow(
              e.value.$1,
              e.value.$2,
              e.value.$3,
              e.value.$4,
              last: e.key == rows.length - 1,
            )),
      ]),
    );
  }
}

// ── _PillSearchField ──────────────────────────────────────────────────────────

class _PillSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final double width;
  final bool isDark;
  final bool dense;
  final bool hasValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _PillSearchField({
    required this.controller,
    required this.hintText,
    required this.width,
    required this.isDark,
    this.dense = false,
    required this.hasValue,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final br = dense ? 20.0 : 24.0;
    return SizedBox(
      width: width,
      child: TextField(
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
            borderSide: BorderSide(
              color: AppColors.primaryBlue,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// (PaymentLinkDialog, channel options, and section labels are now shared
//  from lib/core/widgets/payment_link_dialog.dart)

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

String _formatDate(DateTime dt) {
  final months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
}

String _formatDateLong(DateTime dt) {
  final months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year} · $h:$m';
}

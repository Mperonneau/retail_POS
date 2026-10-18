import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/models/cash_control.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/widgets/cash_history_panel.dart';
import '../../core/widgets/tender_movements_panel.dart';
import '../../core/widgets/tender_stat_card.dart';
import '../../core/widgets/tips_panel.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_close_button.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class RetailCashControlScreen extends ConsumerWidget {
  const RetailCashControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(retailCashSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: state.activeSession == null
            ? _OpenDrawerView(isDark: isDark)
            : state.activeSession!.status == CashSessionStatus.closed
                ? _ClosedSessionView(state: state, isDark: isDark)
                : _ActiveSessionView(state: state, isDark: isDark),
      ),
    );
  }
}

// ─── No Session ───────────────────────────────────────────────────────────────

class _OpenDrawerView extends ConsumerStatefulWidget {
  final bool isDark;
  const _OpenDrawerView({required this.isDark});

  @override
  ConsumerState<_OpenDrawerView> createState() => _OpenDrawerViewState();
}

class _OpenDrawerViewState extends ConsumerState<_OpenDrawerView> {
  final _htgCtrl = TextEditingController();
  final _usdCtrl = TextEditingController();

  @override
  void dispose() {
    _htgCtrl.dispose();
    _usdCtrl.dispose();
    super.dispose();
  }

  void _open() {
    final htg = double.tryParse(_htgCtrl.text) ?? 0;
    final usd = double.tryParse(_usdCtrl.text) ?? 0;
    ref.read(retailCashSessionProvider.notifier).openSession(
          openedBy: 'Gérant',
          openingBalanceHtg: htg,
          openingBalanceUsd: usd,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.point_of_sale_outlined,
                  color: AppColors.amber, size: 44),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Text('Contrôle de caisse',
                style: AppTextStyles.h1(
                    color: widget.isDark
                        ? AppColors.warmWhite
                        : AppColors.primaryBlue)),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Ouvrez le tiroir pour suivre les mouvements d\'espèces de cette session.',
              style: AppTextStyles.body(
                  color:
                      widget.isDark ? AppColors.coolGray : AppColors.darkGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing32),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solde d\'ouverture', style: AppTextStyles.h3()),
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: _htgCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: InputFormatters.decimalAmount,
                    decoration: InputDecoration(
                      labelText: 'Espèces dans le tiroir (HTG)',
                      prefixText: 'HTG ',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                  TextField(
                    controller: _usdCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: InputFormatters.decimalAmount,
                    decoration: InputDecoration(
                      labelText: 'Espèces dans le tiroir (USD) — facultatif',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing24),
                  AppButton(
                    label: 'Ouvrir le tiroir',
                    onPressed: _open,
                    icon: Icons.lock_open_outlined,
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

// ─── Active Session ───────────────────────────────────────────────────────────

enum _MovFilter { all, cashIn, cashOut }

class _ActiveSessionView extends ConsumerStatefulWidget {
  final CashControlState state;
  final bool isDark;
  const _ActiveSessionView({required this.state, required this.isDark});

  @override
  ConsumerState<_ActiveSessionView> createState() => _ActiveSessionViewState();
}

class _ActiveSessionViewState extends ConsumerState<_ActiveSessionView> {
  _MovFilter _filter = _MovFilter.all;
  bool _showUsd = false;
  bool _showMovementLog = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CashMovement> get _filtered {
    var list = widget.state.sessionMovements;
    if (_filter == _MovFilter.cashIn) {
      list = list.where((m) => m.type == CashMovementType.cashIn).toList();
    } else if (_filter == _MovFilter.cashOut) {
      list = list.where((m) => m.type == CashMovementType.cashOut).toList();
    }
    if (_query.isNotEmpty) {
      list = list
          .where((m) =>
              m.description.toLowerCase().contains(_query) ||
              (m.linkedTableNumber?.toLowerCase().contains(_query) ?? false) ||
              (m.linkedWaiterName?.toLowerCase().contains(_query) ?? false) ||
              (m.linkedOrderId?.toLowerCase().contains(_query) ?? false))
          .toList();
    }
    return list;
  }

  int _countFor(_MovFilter f) {
    final all = widget.state.sessionMovements;
    if (f == _MovFilter.cashIn) {
      return all.where((m) => m.type == CashMovementType.cashIn).length;
    }
    if (f == _MovFilter.cashOut) {
      return all.where((m) => m.type == CashMovementType.cashOut).length;
    }
    return all.length;
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.activeSession!;
    final isDark = widget.isDark;
    final filtered = _filtered;
    final tenders = PaymentTender.values;
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;
    final divColor = isDark ? AppColors.darkBorder : const Color(0xFFE8E8E8);
    final chipBg = isDark ? AppColors.darkSurface : const Color(0xFFF0F4FA);

    return Column(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Scrollbar(
              thumbVisibility: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CustomScrollView(
                  primary: true,
                  slivers: [
                // ── Header ────────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 520;
                        final titleBlock = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Contrôle de caisse',
                                style: AppTextStyles.h1(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.primaryBlue)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time_rounded,
                                    size: 13, color: textSecondary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Ouvert à ${_timeStr(session.openedAt)} · ${session.openedBy}',
                                    style: AppTextStyles.caption(
                                        color: textSecondary),
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                        final actions = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _HeaderBtn(
                              icon: Icons.history_rounded,
                              label: 'Historique',
                              isDark: isDark,
                              onTap: () => showCashHistoryPanel(
                                    context,
                                    isDark,
                                    sessionProvider: retailCashSessionProvider,
                                  ),
                            ),
                            _HeaderBtn(
                              icon: Icons.payments_outlined,
                              label: 'Pourboires',
                              isDark: isDark,
                              onTap: () => showTipsPanel(context, isDark),
                            ),
                            _StatusBadge(open: true),
                          ],
                        );
                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleBlock,
                              const SizedBox(height: 12),
                              actions,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // ── Payment methods ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Moyens de paiement — net de la session',
                      style: AppTextStyles.h3(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: LayoutBuilder(builder: (context, c) {
                      final w = c.maxWidth;
                      final cross = w > 1000
                          ? 5
                          : w > 720
                              ? 3
                              : w > 420
                                  ? 2
                                  : 1;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: cross,
                        crossAxisSpacing: AppConstants.spacing12,
                        mainAxisSpacing: AppConstants.spacing12,
                        childAspectRatio: 1.8,
                        children: [
                          for (final t in tenders)
                            TenderStatCard(
                              tender: t,
                              netHtg: state.tenderNetHtg(t),
                              netUsd: state.tenderNetUsd(t),
                              isDark: isDark,
                              onAddMovement: () => _showAddMovementSheet(
                                  context, isDark,
                                  tender: t),
                              onDetails: () => showTenderMovementsPanel(
                                context,
                                movements: state.sessionMovements,
                                tender: t,
                                isDark: isDark,
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                ),

                // ── Drawer summary strip ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Tiroir-caisse physique',
                      style: AppTextStyles.h3(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final chips = <Widget>[
                          _SummaryChip(
                            label: 'Ouverture',
                            htg: session.openingBalanceHtg,
                            usd: session.openingBalanceUsd,
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue,
                            isDark: isDark,
                          ),
                          _SummaryChip(
                            label: 'Entrée de caisse',
                            htg: state.totalIn,
                            usd: state.totalInUsd,
                            color: AppColors.deepGreen,
                            isDark: isDark,
                          ),
                          _SummaryChip(
                            label: 'Sortie de caisse',
                            htg: state.totalOut,
                            usd: state.totalOutUsd,
                            color: AppColors.boldRed,
                            isDark: isDark,
                          ),
                          _SummaryChip(
                            label: 'Attendu',
                            htg: state.expectedBalance,
                            usd: state.expectedBalanceUsd,
                            color: AppColors.amber,
                            isDark: isDark,
                          ),
                        ];
                        if (w >= 720) {
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < chips.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(width: AppConstants.spacing8),
                                  Expanded(child: chips[i]),
                                ],
                              ],
                            ),
                          );
                        }
                        final gap = 8.0;
                        final colW = (w - gap) / 2;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: chips
                              .map((c) => SizedBox(width: colW, child: c))
                              .toList(),
                        );
                      },
                    ),
                  ),
                ),

                // ── Movement log toggle ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: _MovLogToggle(
                    show: _showMovementLog,
                    count: state.sessionMovements.length,
                    isDark: isDark,
                    onToggle: () =>
                        setState(() => _showMovementLog = !_showMovementLog),
                  ),
                ),

                if (_showMovementLog) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final searchField = TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Rechercher par motif, reçu, caissier…',
                              hintStyle: AppTextStyles.caption(),
                              prefixIcon:
                                  const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: _query.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 16),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _query = '');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              filled: true,
                              fillColor: chipBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusInput),
                                borderSide: BorderSide(color: divColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusInput),
                                borderSide: BorderSide(color: divColor),
                              ),
                            ),
                          );
                          final toggles = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _CurrencyToggle(
                                showUsd: _showUsd,
                                onToggle: (v) => setState(() => _showUsd = v),
                                isDark: isDark,
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    _showAddMovementSheet(context, isDark),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Ajouter'),
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.amber),
                              ),
                            ],
                          );
                          if (c.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField,
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: toggles,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: searchField),
                              const SizedBox(width: 8),
                              toggles,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FilterTabRow(
                        selected: _filter,
                        counts: {
                          _MovFilter.all: _countFor(_MovFilter.all),
                          _MovFilter.cashIn: _countFor(_MovFilter.cashIn),
                          _MovFilter.cashOut: _countFor(_MovFilter.cashOut),
                        },
                        onSelect: (f) => setState(() => _filter = f),
                        isDark: isDark,
                      ),
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 40, color: textSecondary),
                              const SizedBox(height: 12),
                              Text(
                                _query.isNotEmpty
                                    ? 'Aucun mouvement pour « $_query »'
                                    : _filter == _MovFilter.cashIn
                                        ? 'Aucune entrée pour le moment.'
                                        : _filter == _MovFilter.cashOut
                                            ? 'Aucune sortie pour le moment.'
                                            : 'Aucun mouvement pour le moment.',
                                style: AppTextStyles.body(color: textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return _MovementTile(
                          movement: m,
                          showUsd: _showUsd,
                          isDark: isDark,
                          onTap: () => _showMovementDetail(context, m, isDark),
                        );
                      },
                    ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Pinned footer ─────────────────────────────────────────────────
        Divider(height: 1, color: divColor),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing12),
          child: AppButton(
            label: 'Fermer le tiroir et rapprocher',
            onPressed: () => context.go(AppRoutes.retailCashReconciliation),
            icon: Icons.lock_outlined,
            variant: AppButtonVariant.secondary,
          ),
        ),
      ],
    );
  }

  void _showAddMovementSheet(BuildContext context, bool isDark,
      {PaymentTender? tender}) {
    showAppBottomSheet(
      context: context,
      child: _AddMovementSheet(
        isDark: isDark,
        sessionId: widget.state.activeSession!.id,
        preselectedTender: tender,
        onSave: (type, amtHtg, amtUsd, tipsHtg, tipsUsd, description, tableNum,
            waiterName, t) {
          ref.read(retailCashSessionProvider.notifier).addMovement(
                type: type,
                amountHtg: amtHtg,
                amountUsd: amtUsd,
                tipsHtg: tipsHtg,
                tipsUsd: tipsUsd,
                description: description,
                linkedTableNumber: tableNum,
                linkedWaiterName: waiterName,
                recordedBy: 'Gérant',
                tender: t,
              );
        },
      ),
    );
  }

  void _showMovementDetail(
      BuildContext context, CashMovement movement, bool isDark) {
    MockSale? sale;
    if (movement.linkedOrderId != null) {
      final saleId = int.tryParse(movement.linkedOrderId!);
      if (saleId != null) {
        final sales = ref.read(mockSalesProvider);
        try {
          sale = sales.firstWhere((s) => s.id == saleId);
        } catch (_) {
          sale = null;
        }
      }
    }

    showAppBottomSheet(
      context: context,
      child: _MovementDetailSheet(
        movement: movement,
        isDark: isDark,
        sale: sale,
      ),
    );
  }
}

// ─── Closed Session ───────────────────────────────────────────────────────────

class _ClosedSessionView extends ConsumerWidget {
  final CashControlState state;
  final bool isDark;
  const _ClosedSessionView({required this.state, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: AppColors.deepGreen, size: 44),
          ),
          const SizedBox(height: AppConstants.spacing24),
          Text('Session fermée',
              style: AppTextStyles.h1(
                  color: isDark ? AppColors.warmWhite : AppColors.primaryBlue)),
          const SizedBox(height: AppConstants.spacing8),
          Text('Le tiroir-caisse a été fermé et rapproché.',
              style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
              textAlign: TextAlign.center),
          const SizedBox(height: AppConstants.spacing32),
          AppButton(
            label: 'Nouvelle session',
            onPressed: () {
              ref.read(retailCashSessionProvider.notifier).openSession(
                    openedBy: 'Gérant',
                    openingBalanceHtg: 0,
                  );
            },
            icon: Icons.lock_open_outlined,
          ),
        ],
      ),
    );
  }
}

// ─── Summary Chip (dual currency) ─────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final double htg;
  final double usd;
  final Color color;
  final bool isDark;

  const _SummaryChip({
    required this.label,
    required this.htg,
    required this.usd,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption(color: color)),
          const SizedBox(height: 3),
          Text(
            CurrencyFormatter.local(context, htg),
            style: AppTextStyles.body(color: color)
                .copyWith(fontWeight: FontWeight.w700, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            '\$${usd.toStringAsFixed(2)}',
            style: AppTextStyles.caption(color: color.withValues(alpha: 0.65))
                .copyWith(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Currency Toggle ──────────────────────────────────────────────────────────

class _CurrencyToggle extends StatelessWidget {
  final bool showUsd;
  final ValueChanged<bool> onToggle;
  final bool isDark;

  const _CurrencyToggle({
    required this.showUsd,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
              label: 'HTG',
              active: !showUsd,
              isDark: isDark,
              onTap: () => onToggle(false)),
          _Pill(
              label: 'USD',
              active: showUsd,
              isDark: isDark,
              onTap: () => onToggle(true)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption(
                  color: active
                      ? AppColors.white
                      : (isDark ? AppColors.coolGray : AppColors.darkGray))
              .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ),
    );
  }
}

// ─── Filter Tab Row ───────────────────────────────────────────────────────────

class _FilterTabRow extends StatelessWidget {
  final _MovFilter selected;
  final Map<_MovFilter, int> counts;
  final ValueChanged<_MovFilter> onSelect;
  final bool isDark;

  const _FilterTabRow({
    required this.selected,
    required this.counts,
    required this.onSelect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (_MovFilter.all, 'Tous', null),
      (_MovFilter.cashIn, 'Entrée de caisse', AppColors.deepGreen),
      (_MovFilter.cashOut, 'Sortie de caisse', AppColors.boldRed),
    ];

    return Row(
      children: tabs.map((t) {
        final isSelected = selected == t.$1;
        final count = counts[t.$1] ?? 0;
        final accentColor =
            t.$3 ?? (isDark ? AppColors.skyBlue : AppColors.primaryBlue);

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onSelect(t.$1),
            child: AnimatedContainer(
              duration: AppConstants.animFast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.4)
                      : (isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFE0E0E0)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.$2,
                    style: AppTextStyles.caption(
                            color: isSelected
                                ? accentColor
                                : (isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray))
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.2)
                            : (isDark
                                ? AppColors.darkBorder
                                : const Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: AppTextStyles.caption(
                                color: isSelected
                                    ? accentColor
                                    : (isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray))
                            .copyWith(
                                fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Header Button (icon + label) ────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _HeaderBtn({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1E2E42) : const Color(0xFFF0F4F8);
    final border = isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD);
    final fg = isDark ? AppColors.coolGray : AppColors.darkGray;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.caption(color: fg)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool open;
  const _StatusBadge({required this.open});

  @override
  Widget build(BuildContext context) {
    final color = open ? AppColors.deepGreen : AppColors.coolGray;
    final label = open ? 'OUVERT' : 'FERMÉ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: AppTextStyles.caption(color: color)
                  .copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── Movement Tile ────────────────────────────────────────────────────────────

class _MovementTile extends StatelessWidget {
  final CashMovement movement;
  final bool showUsd;
  final bool isDark;
  final VoidCallback onTap;

  const _MovementTile({
    required this.movement,
    required this.showUsd,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isIn = m.type == CashMovementType.cashIn;
    final isAdj = m.type == CashMovementType.adjustment;
    final color = isAdj
        ? AppColors.amber
        : isIn
            ? AppColors.deepGreen
            : AppColors.boldRed;
    final icon = isAdj
        ? Icons.tune_outlined
        : isIn
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded;
    final sign = isIn
        ? '+'
        : isAdj
            ? (m.adjustmentAddsToDrawer ? '+' : '−')
            : '-';

    final amountStr = showUsd
        ? '$sign\$${(isIn ? m.totalUsd : m.totalUsd).toStringAsFixed(2)}'
        : '$sign${CurrencyFormatter.local(context, isIn ? m.totalHtg : m.totalHtg)}';

    final subtitle = [
      if (isAdj) m.adjustmentAddsToDrawer ? 'Ajouter' : 'Retirer',
      if (m.linkedTableNumber != null) m.linkedTableNumber!,
      if (m.linkedWaiterName != null) m.linkedWaiterName!,
      _timeStr(m.timestamp),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          m.description,
          style: AppTextStyles.body(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
        ),
        subtitle: Text(subtitle, style: AppTextStyles.caption()),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              amountStr,
              style: AppTextStyles.body(color: color)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 16,
                color: isDark ? AppColors.coolGray : AppColors.darkGray),
          ],
        ),
      ),
    );
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ─── Movement Detail Sheet ────────────────────────────────────────────────────

class _MovementDetailSheet extends StatelessWidget {
  final CashMovement movement;
  final bool isDark;
  final MockSale? sale;

  const _MovementDetailSheet({
    required this.movement,
    required this.isDark,
    this.sale,
  });

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isIn = m.type == CashMovementType.cashIn;
    final isAdj = m.type == CashMovementType.adjustment;
    final color = isAdj
        ? AppColors.amber
        : isIn
            ? AppColors.deepGreen
            : AppColors.boldRed;
    final typeLabel = isAdj
        ? 'Ajustement'
        : isIn
            ? 'Entrée de caisse'
            : 'Sortie de caisse';
    final sign = isIn
        ? '+'
        : isAdj
            ? '~'
            : '-';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isAdj
                      ? Icons.tune_outlined
                      : isIn
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.description,
                        style: AppTextStyles.h2(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.nearBlack)),
                    Text(typeLabel,
                        style: AppTextStyles.caption(color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Amount block ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Montant',
                        style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$sign${CurrencyFormatter.local(context, m.amountHtg)}',
                          style: AppTextStyles.h2(color: color),
                        ),
                        if (m.amountUsd > 0)
                          Text(
                            '$sign\$${m.amountUsd.toStringAsFixed(2)}',
                            style: AppTextStyles.caption(
                                color: color.withValues(alpha: 0.7)),
                          ),
                      ],
                    ),
                  ],
                ),
                if (m.tipsHtg > 0 || m.tipsUsd > 0) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Pourboires',
                          style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+${CurrencyFormatter.local(context, m.tipsHtg)}',
                            style:
                                AppTextStyles.body(color: AppColors.deepGreen)
                                    .copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (m.tipsUsd > 0)
                            Text(
                              '+\$${m.tipsUsd.toStringAsFixed(2)}',
                              style: AppTextStyles.caption(
                                  color: AppColors.deepGreen
                                      .withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total',
                          style: AppTextStyles.caption(
                                  color: isDark
                                      ? AppColors.warmWhite
                                      : AppColors.nearBlack)
                              .copyWith(fontWeight: FontWeight.w700)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$sign${CurrencyFormatter.local(context, m.totalHtg)}',
                            style: AppTextStyles.body(color: color)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (m.totalUsd > 0)
                            Text(
                              '$sign\$${m.totalUsd.toStringAsFixed(2)}',
                              style: AppTextStyles.caption(
                                  color: color.withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Context rows ───────────────────────────────────────────────────
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: 'Heure',
            value: _formatTime(m.timestamp),
            isDark: isDark,
          ),
          _DetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Enregistré par',
            value: m.recordedBy,
            isDark: isDark,
          ),
          if (m.linkedTableNumber != null)
            _DetailRow(
              icon: Icons.tag_outlined,
              label: 'Reçu',
              value: m.linkedTableNumber!,
              isDark: isDark,
            ),
          if (m.linkedWaiterName != null)
            _DetailRow(
              icon: Icons.badge_outlined,
              label: 'Caissier',
              value: m.linkedWaiterName!,
              isDark: isDark,
            ),
          if (m.linkedOrderId != null)
            _DetailRow(
              icon: Icons.receipt_long_outlined,
              label: 'Réf. vente',
              value: '#${m.linkedOrderId!}',
              isDark: isDark,
            ),

          if (sale != null) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSalePanel(context),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text('Voir la vente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  side: BorderSide(
                    color: isDark
                        ? AppColors.skyBlue.withValues(alpha: 0.4)
                        : AppColors.primaryBlue.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusButton)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _openSalePanel(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        barrierDismissible: true,
        barrierLabel: 'Fermer',
        pageBuilder: (_, __, ___) =>
            _SaleSidePanel(sale: sale!, isDark: isDark),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    return '$d at $h:$min';
  }
}

// ─── Sale Side Panel (linked POS sale) ───────────────────────────────────────

class _SaleSidePanel extends StatelessWidget {
  final MockSale sale;
  final bool isDark;

  const _SaleSidePanel({required this.sale, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = AppConstants.sidePanelWidth(
        screenWidth, (screenWidth * 0.65).clamp(280.0, 480.0));
    final itemCount =
        sale.items.fold<int>(0, (s, i) => s + i.quantity);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () {},
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              color: bg,
              elevation: 16,
              shadowColor: Colors.black26,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : const Color(0xFFEEEEEE),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vente n°${sale.id}',
                                  style: AppTextStyles.h2(
                                      color: isDark
                                          ? AppColors.warmWhite
                                          : AppColors.nearBlack),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sale.customerName != null
                                      ? '${sale.customerName} · ${sale.paymentMethod}'
                                      : sale.paymentMethod,
                                  style: AppTextStyles.caption(),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.amber.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              sale.paymentMethod,
                              style: AppTextStyles.caption(color: AppColors.amber)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.person_outline_rounded,
                            label: sale.cashier,
                            isDark: isDark,
                          ),
                          _InfoChip(
                            icon: Icons.schedule_outlined,
                            label: _timeStr(sale.date),
                            isDark: isDark,
                          ),
                          _InfoChip(
                            icon: Icons.inventory_2_outlined,
                            label: '$itemCount articles',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Text(
                        'Lignes',
                        style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray)
                            .copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: sale.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = sale.items[i];
                          final lineHtg = item.priceHtg * item.quantity;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: (isDark
                                            ? AppColors.skyBlue
                                            : AppColors.primaryBlue)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${item.quantity}×',
                                      style: AppTextStyles.caption(
                                              color: isDark
                                                  ? AppColors.skyBlue
                                                  : AppColors.primaryBlue)
                                          .copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: AppTextStyles.body(
                                            color: isDark
                                                ? AppColors.warmWhite
                                                : AppColors.nearBlack),
                                      ),
                                      Text(
                                        '${CurrencyFormatter.local(context, item.priceHtg)} / unit',
                                        style: AppTextStyles.caption(),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.local(context, lineHtg),
                                  style: AppTextStyles.body(
                                          color: isDark
                                              ? AppColors.warmWhite
                                              : AppColors.nearBlack)
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1A2535)
                            : const Color(0xFFF8F9FA),
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : const Color(0xFFEEEEEE),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total de la vente',
                            style: AppTextStyles.body(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            CurrencyFormatter.local(context, sale.totalHtg),
                            style: AppTextStyles.h3(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _timeStr(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _InfoChip(
      {required this.icon, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 13, color: isDark ? AppColors.coolGray : AppColors.darkGray),
        const SizedBox(width: 3),
        Text(label, style: AppTextStyles.caption()),
      ],
    );
  }
}

// ─── Detail Row ───────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.darkGray),
          const SizedBox(width: 8),
          Text('$label:',
              style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack)
                  .copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Movement Sheet ───────────────────────────────────────────────────────

typedef _OnSaveMovement = void Function(
  CashMovementType type,
  double amtHtg,
  double amtUsd,
  double tipsHtg,
  double tipsUsd,
  String description,
  String? tableNum,
  String? waiterName,
  PaymentTender tender,
);

class _AddMovementSheet extends StatefulWidget {
  final bool isDark;
  final String sessionId;
  final PaymentTender? preselectedTender;
  final _OnSaveMovement onSave;

  const _AddMovementSheet({
    required this.isDark,
    required this.sessionId,
    required this.onSave,
    this.preselectedTender,
  });

  @override
  State<_AddMovementSheet> createState() => _AddMovementSheetState();
}

class _AddMovementSheetState extends State<_AddMovementSheet> {
  CashMovementType _type = CashMovementType.cashIn;
  late PaymentTender _tender;

  @override
  void initState() {
    super.initState();
    _tender = widget.preselectedTender ?? PaymentTender.cashHtg;
  }

  final _htgCtrl = TextEditingController();
  final _usdCtrl = TextEditingController();
  final _tipsHtgCtrl = TextEditingController();
  final _tipsUsdCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tableCtrl = TextEditingController();
  final _waiterCtrl = TextEditingController();

  bool get _showTableFields => _type == CashMovementType.cashIn;

  /// When type is adjustment: add vs remove from drawer (stored as signed amounts).
  bool _adjustmentAdds = true;

  @override
  void dispose() {
    _htgCtrl.dispose();
    _usdCtrl.dispose();
    _tipsHtgCtrl.dispose();
    _tipsUsdCtrl.dispose();
    _descriptionCtrl.dispose();
    _tableCtrl.dispose();
    _waiterCtrl.dispose();
    super.dispose();
  }

  void _save() {
    var amtHtg = double.tryParse(_htgCtrl.text) ?? 0;
    var amtUsd = double.tryParse(_usdCtrl.text) ?? 0;
    final description = _descriptionCtrl.text.trim();
    if (description.isEmpty) return;
    if (_type == CashMovementType.adjustment) {
      if (amtHtg <= 0 && amtUsd <= 0) return;
      if (!_adjustmentAdds) {
        amtHtg = -amtHtg;
        amtUsd = -amtUsd;
      }
    } else if (amtHtg <= 0 && amtUsd <= 0) {
      return;
    }
    widget.onSave(
      _type,
      amtHtg,
      amtUsd,
      double.tryParse(_tipsHtgCtrl.text) ?? 0,
      double.tryParse(_tipsUsdCtrl.text) ?? 0,
      description,
      _tableCtrl.text.trim().isEmpty ? null : _tableCtrl.text.trim(),
      _waiterCtrl.text.trim().isEmpty ? null : _waiterCtrl.text.trim(),
      _tender,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        top: AppConstants.spacing24,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              widget.preselectedTender != null
                  ? 'Ajouter — ${widget.preselectedTender!.label}'
                  : 'Ajouter un mouvement de caisse',
              style: AppTextStyles.h2(
                  color: widget.isDark
                      ? AppColors.warmWhite
                      : AppColors.nearBlack)),
          const SizedBox(height: AppConstants.spacing16),

          // Tender selector (locked if preselected)
          if (widget.preselectedTender != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: AppConstants.spacing12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFCCCCCC)),
                borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                color: widget.isDark
                    ? AppColors.darkSurface
                    : const Color(0xFFF5F5F5),
              ),
              child: Row(
                children: [
                  Icon(
                    paymentTenderIcon(widget.preselectedTender!),
                    size: 16,
                    color: paymentTenderColor(widget.preselectedTender!,
                        isDark: widget.isDark),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.preselectedTender!.label,
                    style: AppTextStyles.body(
                        color: widget.isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack),
                  ),
                  const Spacer(),
                  Icon(Icons.lock_outline,
                      size: 14,
                      color: widget.isDark
                          ? AppColors.coolGray
                          : AppColors.darkGray),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacing12),
              child: DropdownButtonFormField<PaymentTender>(
                // ignore: deprecated_member_use
                value: _tender,
                decoration: InputDecoration(
                  labelText: 'Moyen de paiement',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput),
                  ),
                ),
                items: PaymentTender.values
                    .map(
                        (t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) => setState(() => _tender = v ?? _tender),
              ),
            ),

          // Type selector
          Row(
            children: [
              Expanded(
                child: _TypeBtn(
                  label: 'Entrée de caisse',
                  icon: Icons.arrow_downward_rounded,
                  selected: _type == CashMovementType.cashIn,
                  color: AppColors.deepGreen,
                  onTap: () => setState(() => _type = CashMovementType.cashIn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TypeBtn(
                  label: 'Sortie de caisse',
                  icon: Icons.arrow_upward_rounded,
                  selected: _type == CashMovementType.cashOut,
                  color: AppColors.boldRed,
                  onTap: () => setState(() => _type = CashMovementType.cashOut),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TypeBtn(
                  label: 'Ajustement',
                  icon: Icons.tune_outlined,
                  selected: _type == CashMovementType.adjustment,
                  color: AppColors.amber,
                  onTap: () =>
                      setState(() => _type = CashMovementType.adjustment),
                ),
              ),
            ],
          ),
          if (_type == CashMovementType.adjustment) ...[
            const SizedBox(height: AppConstants.spacing12),
            Text(
              'Correction',
              style: AppTextStyles.caption(
                color: widget.isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Ajouter au tiroir'),
                  icon: Icon(Icons.add_circle_outline, size: 16),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Retirer du tiroir'),
                  icon: Icon(Icons.remove_circle_outline, size: 16),
                ),
              ],
              selected: {_adjustmentAdds},
              onSelectionChanged: (s) =>
                  setState(() => _adjustmentAdds = s.first),
            ),
          ],
          const SizedBox(height: AppConstants.spacing12),

          // Amounts
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _htgCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  decoration: InputDecoration(
                    labelText: 'Montant (HTG) *',
                    prefixText: 'HTG ',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _usdCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  decoration: InputDecoration(
                    labelText: 'Montant (USD)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                ),
              ),
            ],
          ),

          // Tips (cash in only)
          if (_showTableFields) ...[
            const SizedBox(height: AppConstants.spacing12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tipsHtgCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: InputFormatters.decimalAmount,
                    decoration: InputDecoration(
                      labelText: 'Tips (HTG)',
                      prefixText: 'HTG ',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tipsUsdCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: InputFormatters.decimalAmount,
                    decoration: InputDecoration(
                      labelText: 'Tips (USD)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppConstants.spacing12),

          // Description
          TextField(
            controller: _descriptionCtrl,
            decoration: InputDecoration(
              labelText: 'Description *',
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusInput)),
            ),
          ),

          if (_showTableFields) ...[
            const SizedBox(height: AppConstants.spacing12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tableCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reçu / réf. (facultatif)',
                      hintText: 'e.g. RCP-2042',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _waiterCtrl,
                    decoration: InputDecoration(
                      labelText: 'Caissier',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppConstants.spacing24),
          AppButton(label: 'Enregistrer le mouvement', onPressed: _save),
        ],
      ),
    );
  }
}

// ─── Type Button ──────────────────────────────────────────────────────────────

class _TypeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color
              : (isDark ? AppColors.darkSurface : AppColors.white),
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          border: Border.all(
              color: selected
                  ? color
                  : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? AppColors.white
                    : (isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(
                  color: selected
                      ? AppColors.white
                      : (isDark ? AppColors.coolGray : AppColors.darkGray)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Movement Log Toggle Row ──────────────────────────────────────────────────

class _MovLogToggle extends StatelessWidget {
  final bool show;
  final int count;
  final bool isDark;
  final VoidCallback onToggle;
  const _MovLogToggle({
    required this.show,
    required this.count,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = isDark ? AppColors.coolGray : AppColors.darkGray;
    final bg = isDark ? AppColors.darkSurface : const Color(0xFFF0F4FA);
    final border = isDark ? AppColors.darkBorder : const Color(0xFFD8E0EE);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 16, color: textSecondary),
            const SizedBox(width: 8),
            Text(
              'Journal des mouvements',
              style: AppTextStyles.body(color: textSecondary)
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.darkBorder : const Color(0xFFE0E8F0))
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.caption(color: textSecondary)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 10),
              ),
            ),
            const Spacer(),
            Icon(
              show
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

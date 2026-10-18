import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../models/paylink.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/list_page_nav.dart';
import '../../widgets/payment_link_dialog.dart';
import 'new_paylink_modal.dart';
import 'paylink_detail_sheet.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class PayLinkScreen extends ConsumerStatefulWidget {
  final StateNotifierProvider<PayLinkNotifier, PayLinkState> payLinkProvider;
  final StateNotifierProvider<CustomerNotifier, CustomerState> customerProvider;

  const PayLinkScreen({
    super.key,
    required this.payLinkProvider,
    required this.customerProvider,
  });

  @override
  ConsumerState<PayLinkScreen> createState() => _PayLinkScreenState();
}

class _PayLinkScreenState extends ConsumerState<PayLinkScreen> {
  int _tab = 0; // 0=active, 1=paid, 2=inactive
  int _page = 0;
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  static const _kPageSize = 15;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _query = _searchCtrl.text.trim().toLowerCase();
        _page = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  List<PayLink> _filtered(List<PayLink> src) {
    if (_query.isEmpty) return src;
    return src.where((l) {
      return l.customerName.toLowerCase().contains(_query) ||
          l.customerPhone.contains(_query) ||
          l.reference.toLowerCase().contains(_query) ||
          l.sentTo.toLowerCase().contains(_query);
    }).toList();
  }

  // ── UI helpers ───────────────────────────────────────────────────────────────

  Future<void> _openNewPaylink() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final created = await showNewPayLinkModal(
      context,
      isDark: isDark,
      payLinkProvider: widget.payLinkProvider,
      customerProvider: widget.customerProvider,
    );
    if (!mounted || created == null) return;
    final path = (created.paymentUrl != null && created.paymentUrl!.isNotEmpty)
        ? created.paymentUrl!
        : buildStandalonePaylinkPath(created.id);
    await showPaymentLinkSuccessDialog(
      context,
      isDark: isDark,
      title: 'Le lien ${created.reference} a été créé.',
      pathOrUrl: path,
      subtitle: 'Copiez ou partagez le lien avec le client ou le payeur si besoin.',
    );
  }

  void _showResendSuccess(PayLink link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.deepGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.deepGreen, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Lien renvoyé'),
          ],
        ),
        content: Text('Le lien ${link.reference} a été renvoyé à ${link.sentTo}.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.deepGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirm(PayLink link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Annuler le lien de paiement ?'),
        content: Text(
            'Annuler ${link.reference} pour ${link.customerName} ? Le payeur ne pourra plus payer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(widget.payLinkProvider.notifier).cancel(link.id);
              _showCanceledModal(link);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.boldRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Annuler le lien'),
          ),
        ],
      ),
    );
  }

  void _showCanceledModal(PayLink link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.coolGray),
            SizedBox(width: 8),
            Text('Lien annulé'),
          ],
        ),
        content: Text('${link.reference} a été annulé.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(widget.payLinkProvider);

    final tabs = [state.active, state.paid, state.inactive];
    final tabLabels = ['Actif', 'Payé', 'Inactif'];
    final filtered = _filtered(tabs[_tab]);

    final pageCount = (filtered.length / _kPageSize).ceil().clamp(1, 999);
    final safePage = _page.clamp(0, pageCount - 1);
    final start = safePage * _kPageSize;
    final end = (start + _kPageSize).clamp(0, filtered.length);
    final pageItems = filtered.sublist(start, end);
    final narrow =
        MediaQuery.sizeOf(context).width <= AppConstants.mobileBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────────────
          _PageHeader(
            isDark: isDark,
            compact: narrow,
            searchOpen: _searchOpen,
            searchController: _searchCtrl,
            onToggleSearch: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _searchCtrl.clear();
            }),
            onNewPaylink: _openNewPaylink,
          ),

          // ── Tab toggle + search ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TabToggle(
                  labels: tabLabels,
                  counts: [
                    state.active.length,
                    state.paid.length,
                    state.inactive.length,
                  ],
                  amounts: [
                    state.totalActivePendingHtg,
                    state.totalPaidHtg,
                    null,
                  ],
                  selectedIndex: _tab,
                  isDark: isDark,
                  onChanged: (i) => setState(() {
                    _tab = i;
                    _page = 0;
                  }),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SearchField(
                      controller: _searchCtrl,
                      isDark: isDark,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Table header (desktop). Phones use cards, like Devis. ─────────
          if (!narrow) const _TableHeader(),

          // ── Paylink list ───────────────────────────────────────────────────
          Expanded(
            child: pageItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_off_rounded,
                            size: 36,
                            color: isDark ? AppColors.coolGray : AppColors.darkGray),
                        const SizedBox(height: 10),
                        Text(
                          _query.isNotEmpty
                              ? 'Aucun résultat pour « $_query »'
                              : 'Aucun lien ${tabLabels[_tab].toLowerCase()}',
                          style: AppTextStyles.body(
                              color: isDark ? AppColors.coolGray : AppColors.darkGray),
                        ),
                        if (_tab == 0 && _query.isEmpty) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _openNewPaylink,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Créer un lien de paiement'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      narrow ? AppConstants.spacing16 : 0,
                      narrow ? AppConstants.spacing8 : 0,
                      narrow ? AppConstants.spacing16 : 0,
                      narrow ? AppConstants.spacing16 : 4,
                    ),
                    itemCount: pageItems.length +
                        (narrow && pageCount > 1 ? 1 : 0),
                    separatorBuilder: (_, i) {
                      if (narrow) {
                        return SizedBox(
                          height: pageCount > 1 && i >= pageItems.length - 1
                              ? AppConstants.spacing16
                              : AppConstants.spacing8,
                        );
                      }
                      return Divider(
                        height: 1,
                        indent: 24,
                        endIndent: 24,
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFEEEEEE),
                      );
                    },
                    itemBuilder: (context, i) {
                      if (i >= pageItems.length) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: ListPageNav(
                            isDark: isDark,
                            currentPage: safePage + 1,
                            totalPages: pageCount,
                            onPrevious: safePage > 0
                                ? () => setState(() => _page = safePage - 1)
                                : null,
                            onNext: safePage < pageCount - 1
                                ? () => setState(() => _page = safePage + 1)
                                : null,
                          ),
                        );
                      }
                      final link = pageItems[i];
                      if (narrow) {
                        return _PayLinkCard(
                          link: link,
                          isDark: isDark,
                          isActive: _tab == 0,
                          onTap: () => showPayLinkDetail(
                            context,
                            link: link,
                            payLinkProvider: widget.payLinkProvider,
                          ),
                          onResend: () => _showResendSuccess(link),
                          onCancel: () => _showCancelConfirm(link),
                        );
                      }
                      return _PayLinkRow(
                        link: link,
                        isDark: isDark,
                        isActive: _tab == 0,
                        onTap: () => showPayLinkDetail(
                          context,
                          link: link,
                          payLinkProvider: widget.payLinkProvider,
                        ),
                        onResend: () => _showResendSuccess(link),
                        onCancel: () => _showCancelConfirm(link),
                      );
                    },
                  ),
          ),

          // Desktop keeps the numbered pager. Mobile uses the list footer.
          if (!narrow && pageCount > 1)
            _Pagination(
              currentPage: safePage,
              pageCount: pageCount,
              isDark: isDark,
              onPageChanged: (p) => setState(() => _page = p),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Page header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final bool isDark;
  final bool compact;
  final bool searchOpen;
  final TextEditingController searchController;
  final VoidCallback onToggleSearch;
  final VoidCallback onNewPaylink;

  const _PageHeader({
    required this.isDark,
    required this.compact,
    required this.searchOpen,
    required this.searchController,
    required this.onToggleSearch,
    required this.onNewPaylink,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Liens', style: AppTextStyles.h1(color: ink)),
                    const SizedBox(height: 2),
                    Text(
                      'Envoyer des liens de paiement aux clients',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(color: AppColors.coolGray),
                    ),
                  ],
                ),
              ),
              if (compact) ...[
                _SearchToggle(
                  isDark: isDark,
                  open: searchOpen,
                  onTap: onToggleSearch,
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: onNewPaylink,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(compact ? 'Lien paiement' : 'Nouveau lien de paiement'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          if (compact && searchOpen) ...[
            const SizedBox(height: 10),
            _SearchField(
              controller: searchController,
              isDark: isDark,
              autofocus: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchToggle extends StatelessWidget {
  const _SearchToggle({
    required this.isDark,
    required this.open,
    required this.onTap,
  });

  final bool isDark;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = open
        ? AppColors.primaryBlue
        : (isDark ? AppColors.warmWhite : AppColors.nearBlack);
    return Tooltip(
      message: 'Rechercher',
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.search_rounded, size: 20, color: ink),
          ),
        ),
      ),
    );
  }
}

// ─── Tab toggle ───────────────────────────────────────────────────────────────

class _TabToggle extends StatelessWidget {
  final List<String> labels;
  final List<int> counts;

  /// Monetary total per tab. Use `null` to hide the amount for a tab.
  final List<double?> amounts;
  final int selectedIndex;
  final bool isDark;
  final void Function(int) onChanged;

  const _TabToggle({
    required this.labels,
    required this.counts,
    required this.amounts,
    required this.selectedIndex,
    required this.isDark,
    required this.onChanged,
  });

  static const _tabColors = [
    AppColors.amber,       // Active
    AppColors.deepGreen,   // Paid
    AppColors.coolGray,    // Inactive
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFDDE0E5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: labels.asMap().entries.map((e) {
          final i = e.key;
          final selected = i == selectedIndex;
          final accentColor = _tabColors[i];
          final textColor = selected
              ? (isDark ? AppColors.warmWhite : AppColors.nearBlack)
              : (isDark ? AppColors.coolGray : AppColors.darkGray);
          final amount = amounts[i];

          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: AppConstants.animFast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? const Color(0xFF1E2433) : AppColors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: selected
                    ? Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 1,
                      )
                    : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Label + count ──────────────────────────────────────
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.value,
                        style: AppTextStyles.caption(color: textColor).copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: selected
                              ? accentColor.withValues(alpha: 0.15)
                              : (isDark
                                  ? AppColors.darkBackground
                                  : const Color(0xFFE0E3E8)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          counts[i].toString(),
                          style: AppTextStyles.caption(
                            color: selected
                                ? accentColor
                                : (isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray),
                          ).copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  // ── Amount ─────────────────────────────────────────────
                  if (amount != null && amount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.local(context, amount),
                      style: AppTextStyles.caption(
                        color: selected ? accentColor : AppColors.coolGray,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      '—',
                      style: AppTextStyles.caption(color: AppColors.coolGray)
                          .copyWith(fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final bool autofocus;

  const _SearchField({
    required this.controller,
    required this.isDark,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        style: AppTextStyles.body(color: isDark ? AppColors.warmWhite : AppColors.nearBlack)
            .copyWith(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Rechercher nom, réf., téléphone…',
          hintStyle: AppTextStyles.caption(color: AppColors.coolGray)
              .copyWith(fontSize: 12),
          prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.coolGray),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: controller.clear,
                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.coolGray),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          isDense: true,
          filled: true,
          fillColor: isDark ? AppColors.darkSurface : AppColors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : const Color(0xFFDDE0E5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppColors.primaryBlue, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─── Table header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('CLIENT / RÉF',
                style: AppTextStyles.caption(color: color)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5)),
          ),
          Expanded(
            flex: 3,
            child: Text('DATE',
                style: AppTextStyles.caption(color: color)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5)),
          ),
          Expanded(
            flex: 3,
            child: Text('MONTANT',
                textAlign: TextAlign.right,
                style: AppTextStyles.caption(color: color)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

// ─── Paylink row ──────────────────────────────────────────────────────────────

class _PayLinkRow extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  const _PayLinkRow({
    required this.link,
    required this.isDark,
    required this.isActive,
    required this.onTap,
    required this.onResend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final mutedColor = isDark ? AppColors.coolGray : AppColors.darkGray;

    return InkWell(
      onTap: onTap,
      splashColor: AppColors.primaryBlue.withValues(alpha: 0.05),
      highlightColor: AppColors.primaryBlue.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
        child: Row(
          children: [
            // ── Client + ref ───────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.customerName,
                    style: AppTextStyles.body(color: textColor)
                        .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    link.reference,
                    style: AppTextStyles.caption(color: mutedColor)
                        .copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),

            // ── Date ───────────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Text(
                _shortDate(link.createdAt),
                style: AppTextStyles.caption(color: mutedColor)
                    .copyWith(fontSize: 12),
              ),
            ),

            // ── Amount ─────────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Text(
                CurrencyFormatter.local(context, link.amountHtg),
                textAlign: TextAlign.right,
                style: AppTextStyles.body(color: textColor)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),

            // ── Action icons ───────────────────────────────────────────────
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isActive) ...[
                    _ActionIcon(
                      icon: Icons.refresh_rounded,
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                      tooltip: 'Renvoyer',
                      onTap: onResend,
                    ),
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.cancel_outlined,
                      color: AppColors.boldRed,
                      tooltip: 'Annuler',
                      onTap: onCancel,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: mutedColor,
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

class _PayLinkCard extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  const _PayLinkCard({
    required this.link,
    required this.isDark,
    required this.isActive,
    required this.onTap,
    required this.onResend,
    required this.onCancel,
  });

  String get _channelLabel {
    switch (link.channel) {
      case PayLinkChannel.whatsApp:
        return 'WhatsApp';
      case PayLinkChannel.email:
        return 'E-mail';
      case PayLinkChannel.sms:
        return 'SMS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : const Color(0xFFE8E8E8),
            ),
            boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
              vertical: AppConstants.spacing12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        link.reference,
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ).copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatter.local(context, link.amountHtg),
                      maxLines: 1,
                      softWrap: false,
                      style: AppTextStyles.body(color: ink).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  link.customerName,
                  style: AppTextStyles.body(color: ink).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_shortDate(link.createdAt)} · $_channelLabel',
                        style: AppTextStyles.caption(color: muted)
                            .copyWith(fontSize: 11),
                      ),
                    ),
                    if (isActive) ...[
                      _ActionIcon(
                        icon: Icons.refresh_rounded,
                        color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                        tooltip: 'Renvoyer',
                        onTap: onResend,
                      ),
                      const SizedBox(width: 4),
                      _ActionIcon(
                        icon: Icons.cancel_outlined,
                        color: AppColors.boldRed,
                        tooltip: 'Annuler',
                        onTap: onCancel,
                      ),
                    ],
                    Icon(Icons.chevron_right_rounded, size: 18, color: muted),
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

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

// ─── Pagination ───────────────────────────────────────────────────────────────

class _Pagination extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final bool isDark;
  final void Function(int) onPageChanged;

  const _Pagination({
    required this.currentPage,
    required this.pageCount,
    required this.isDark,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mutedColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final activeColor = AppColors.primaryBlue;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE4E7EC);

    // Show at most 5 page numbers around current page.
    final pages = _visiblePages(currentPage, pageCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ← Prev
          _PagBtn(
            enabled: currentPage > 0,
            isDark: isDark,
            onTap: () => onPageChanged(currentPage - 1),
            surface: surfaceColor,
            border: borderColor,
            child: Icon(Icons.chevron_left_rounded, size: 16, color: mutedColor),
          ),
          const SizedBox(width: 4),

          ...pages.map((p) {
            if (p == -1) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('…',
                    style: AppTextStyles.caption(color: mutedColor)
                        .copyWith(fontSize: 12)),
              );
            }
            final isSelected = p == currentPage;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _PagBtn(
                enabled: !isSelected,
                isDark: isDark,
                filled: isSelected,
                fillColor: activeColor,
                onTap: () => onPageChanged(p),
                surface: surfaceColor,
                border: borderColor,
                child: Text(
                  '${p + 1}',
                  style: AppTextStyles.caption(
                    color: isSelected ? AppColors.white : mutedColor,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            );
          }),

          const SizedBox(width: 4),
          // → Next
          _PagBtn(
            enabled: currentPage < pageCount - 1,
            isDark: isDark,
            onTap: () => onPageChanged(currentPage + 1),
            surface: surfaceColor,
            border: borderColor,
            child: Icon(Icons.chevron_right_rounded, size: 16, color: mutedColor),
          ),
        ],
      ),
    );
  }

  List<int> _visiblePages(int current, int total) {
    if (total <= 7) return List.generate(total, (i) => i);
    final result = <int>[];
    if (current <= 3) {
      result.addAll([0, 1, 2, 3, 4, -1, total - 1]);
    } else if (current >= total - 4) {
      result.addAll([0, -1, total - 5, total - 4, total - 3, total - 2, total - 1]);
    } else {
      result.addAll([0, -1, current - 1, current, current + 1, -1, total - 1]);
    }
    return result;
  }
}

class _PagBtn extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final bool isDark;
  final bool filled;
  final Color? fillColor;
  final VoidCallback onTap;
  final Color surface;
  final Color border;

  const _PagBtn({
    required this.child,
    required this.enabled,
    required this.isDark,
    this.filled = false,
    this.fillColor,
    required this.onTap,
    required this.surface,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: filled ? fillColor : surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: filled ? (fillColor ?? border) : border,
          ),
        ),
        alignment: Alignment.center,
        child: Opacity(opacity: enabled || filled ? 1.0 : 0.35, child: child),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _shortDate(DateTime d) {
  final months = ['janv.','févr.','mars','avr.','mai','juin','juil.','août','sept.','oct.','nov.','déc.'];
  return '${d.day} ${months[d.month - 1]}';
}

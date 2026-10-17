import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import 'customer_detail_screen.dart';

class CollectionsDashboardScreen extends ConsumerWidget {
  final String formRoute;

  const CollectionsDashboardScreen({super.key, required this.formRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final withBalance = state.customersWithBalance;
    final blocked = state.blockedCustomers;
    final totalOwed = state.totalOutstandingHtg;
    final countWithBalance =
        state.customers.where((c) => state.balanceFor(c.id) > 0).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recouvrements',
                style: AppTextStyles.h1(
                    color:
                        isDark ? AppColors.warmWhite : AppColors.primaryBlue)),
            const SizedBox(height: AppConstants.spacing8),
            Text('Soldes de crédit impayés de tous les clients.',
                style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: AppConstants.spacing24),

            // Summary row
            Row(
              children: [
                _SummaryBox(
                  label: 'Total dû',
                  value: CurrencyFormatter.local(context, totalOwed),
                  color: AppColors.boldRed,
                  isDark: isDark,
                ),
                const SizedBox(width: AppConstants.spacing12),
                _SummaryBox(
                  label: 'Clients débiteurs',
                  value: '$countWithBalance',
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  isDark: isDark,
                ),
                const SizedBox(width: AppConstants.spacing12),
                _SummaryBox(
                  label: 'Comptes bloqués',
                  value: '${blocked.length}',
                  color:
                      blocked.isEmpty ? AppColors.deepGreen : AppColors.amber,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing24),

            Expanded(
              child: withBalance.isEmpty
                  ? const EmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Tous les comptes sont réglés',
                      message: 'Aucun solde impayé pour le moment.',
                    )
                  : ListView(
                      children: [
                        Text('Soldes impayés',
                            style: AppTextStyles.h2(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack)),
                        const SizedBox(height: AppConstants.spacing12),
                        ...withBalance.map((c) {
                          final balance = state.balanceFor(c.id);
                          return Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppConstants.spacing8),
                            child: AppCard(
                              onTap: () => _openDetail(context, c, isDark),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.name,
                                                style: AppTextStyles.body(
                                                        color: isDark
                                                            ? AppColors
                                                                .warmWhite
                                                            : AppColors
                                                                .nearBlack)
                                                    .copyWith(
                                                        fontWeight:
                                                            FontWeight.w600),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (c.isCreditBlocked)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.boldRed
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text('BLOQUÉ',
                                                    style:
                                                        AppTextStyles.caption(
                                                                color: AppColors
                                                                    .boldRed)
                                                            .copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                              ),
                                          ],
                                        ),
                                        Text(c.phone,
                                            style: AppTextStyles.caption()),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        CurrencyFormatter.local(context, balance),
                                        style: AppTextStyles.body(
                                                color: AppColors.boldRed)
                                            .copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                      Text('doit',
                                          style: AppTextStyles.caption()),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18,
                                      color: isDark
                                          ? AppColors.coolGray
                                          : AppColors.darkGray),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (blocked.isNotEmpty) ...[
                          const SizedBox(height: AppConstants.spacing24),
                          Text('Comptes bloqués',
                              style:
                                  AppTextStyles.h2(color: AppColors.boldRed)),
                          const SizedBox(height: AppConstants.spacing12),
                          ...blocked.map((c) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppConstants.spacing8),
                                child: AppCard(
                                  onTap: () => _openDetail(context, c, isDark),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.boldRed
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.block_outlined,
                                            color: AppColors.boldRed, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name,
                                                style: AppTextStyles.body(
                                                    color: isDark
                                                        ? AppColors.warmWhite
                                                        : AppColors.nearBlack)),
                                            if (c.blockedReason != null)
                                              Text(c.blockedReason!,
                                                  style:
                                                      AppTextStyles.caption()),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, Customer c, bool isDark) {
    showAppBottomSheet(
      context: context,
      child: CustomerDetailSheet(
        customer: c,
        isDark: isDark,
        formRoute: formRoute,
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _SummaryBox({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption(color: color)),
            const SizedBox(height: 4),
            Text(value,
                style: AppTextStyles.body(color: color)
                    .copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

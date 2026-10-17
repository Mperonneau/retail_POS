import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/models/customer.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/stat_card.dart';

class RetailDashboard extends ConsumerWidget {
  const RetailDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(mockProductsProvider);
    final sales = ref.watch(mockSalesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalRevenue = sales.fold<double>(0, (s, sale) => s + sale.totalHtg);
    final itemsSold = sales.fold<int>(0, (s, sale) => s + sale.items.fold(0, (ss, i) => ss + i.quantity));
    final lowStockCount = products.where((p) => p.isLowStock).length;
    final customerState = ref.watch(customerProvider);
    final totalOwed = customerState.totalOutstandingHtg;
    final withBalance = customerState.customersWithBalance.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tableau de bord', style: AppTextStyles.h1(
              color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
            )),
            const SizedBox(height: AppConstants.spacing24),
            if (totalOwed > 0) ...[
              AppCard(
                onTap: () => context.go(AppRoutes.retailCollections),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.boldRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.boldRed, size: 20),
                    ),
                    const SizedBox(width: AppConstants.spacing12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Crédit impayé',
                              style: AppTextStyles.body(
                                      color: isDark
                                          ? AppColors.warmWhite
                                          : AppColors.nearBlack)
                                  .copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            '$withBalance client${withBalance == 1 ? '' : 's'} · ${CurrencyFormatter.local(context, totalOwed)} dû',
                            style: AppTextStyles.caption(color: AppColors.boldRed),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacing24),
            ],
            // Stats
            LayoutBuilder(builder: (context, constraints) {
              final count = constraints.maxWidth > 600 ? 4 : 2;
              return GridView.count(
                crossAxisCount: count,
                crossAxisSpacing: AppConstants.spacing12,
                mainAxisSpacing: AppConstants.spacing12,
                childAspectRatio: count == 4 ? 1.45 : 1.35,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StatCard(title: "Ventes du jour", value: CurrencyFormatter.local(context, totalRevenue), percentChange: 14.2, icon: Icons.point_of_sale_outlined, iconColor: AppColors.deepGreen, iconBackground: AppColors.deepGreen.withValues(alpha: 0.1)),
                  StatCard(title: 'Articles vendus', value: '$itemsSold', subtitle: 'unités aujourd\'hui', icon: Icons.shopping_bag_outlined, iconColor: AppColors.primaryBlue),
                  StatCard(title: 'Alertes de stock bas', value: '$lowStockCount', subtitle: 'articles à recommander', icon: Icons.warning_amber_rounded, iconColor: AppColors.boldRed, iconBackground: AppColors.boldRed.withValues(alpha: 0.1)),
                  StatCard(title: 'Espèces dans le tiroir', value: CurrencyFormatter.local(context, 15800), subtitle: 'Roseline\'s session', icon: Icons.account_balance_wallet_outlined, iconColor: AppColors.amber, iconBackground: AppColors.amber.withValues(alpha: 0.1)),
                ],
              );
            }),
            const SizedBox(height: AppConstants.spacing32),
            // Quick actions
            SectionHeader(title: 'Actions rapides'),
            const SizedBox(height: AppConstants.spacing16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  (Icons.point_of_sale_outlined, 'Nouvelle vente', AppRoutes.retailPos, AppColors.amber),
                  (Icons.inventory_outlined, 'Produits', AppRoutes.retailProducts, AppColors.primaryBlue),
                  (Icons.warehouse_outlined, 'Inventaire', AppRoutes.retailInventory, AppColors.deepGreen),
                  (Icons.people_outline, 'Clients', AppRoutes.retailCustomers, AppColors.darkGray),
                  (Icons.bar_chart_outlined, 'Rapports', AppRoutes.retailReports, AppColors.boldRed),
                ].map((a) => Padding(
                  padding: const EdgeInsets.only(right: AppConstants.spacing12),
                  child: GestureDetector(
                    onTap: () => context.go(a.$3),
                    child: Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : AppColors.white,
                        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                        boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 44, height: 44,
                          decoration: BoxDecoration(color: a.$4.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Icon(a.$1, color: a.$4, size: 22)),
                        const SizedBox(height: 8),
                        Text(a.$2, style: AppTextStyles.caption(), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: AppConstants.spacing32),
            // Top products
            SectionHeader(title: 'Produits du jour'),
            const SizedBox(height: AppConstants.spacing16),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ('Riz Blanc 25kg', 8, 25600.0),
                  ('Prestige Beer', 24, 4320.0),
                  ('Huile Végétale', 15, 9000.0),
                  ('Savon Dettol', 10, 1500.0),
                  ('Coca-Cola', 18, 2160.0),
                ].asMap().entries.map((e) {
                  final i = e.key;
                  final item = e.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.skyBlue.withValues(alpha: 0.15) : AppColors.lightBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(child: Text('${i + 1}', style: AppTextStyles.caption(
                                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                              ).copyWith(fontWeight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(item.$1, style: AppTextStyles.body(
                              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                            ))),
                            Text('${item.$2} unités', style: AppTextStyles.caption()),
                            const SizedBox(width: 16),
                            Text(CurrencyFormatter.local(context, item.$3), style: AppTextStyles.body(
                              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                            ).copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (i < 4) const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

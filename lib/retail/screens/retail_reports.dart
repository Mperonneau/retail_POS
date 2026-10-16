import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';

class RetailReports extends ConsumerWidget {
  const RetailReports({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final products = ref.watch(mockProductsProvider);
    final totalInventoryValue = products.fold<double>(0, (s, p) => s + p.costHtg * p.stockQuantity);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Retail Reports', style: AppTextStyles.h1(
              color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
            )),
            const SizedBox(height: AppConstants.spacing24),
            // KPIs
            LayoutBuilder(builder: (context, constraints) {
              final count = constraints.maxWidth > 600 ? 4 : 2;
              return GridView.count(
                crossAxisCount: count,
                crossAxisSpacing: AppConstants.spacing12,
                mainAxisSpacing: AppConstants.spacing12,
                childAspectRatio: count == 4 ? 1.8 : 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _KpiCard('Total Revenue', 'HTG 248,500', '+14.2%', true),
                  _KpiCard('Gross Profit', 'HTG 68,300', '+9.8%', true),
                  _KpiCard('Transactions', '152', '+18 vs last week', false),
                  _KpiCard('Inventory Value', CurrencyFormatter.compact(totalInventoryValue), null, false),
                ],
              );
            }),
            const SizedBox(height: AppConstants.spacing32),
            // Sales chart
            SectionHeader(title: 'Daily Sales — This Week'),
            const SizedBox(height: AppConstants.spacing16),
            AppCard(child: SizedBox(height: 200, child: _buildSalesChart(isDark))),
            const SizedBox(height: AppConstants.spacing32),
            // Top products
            SectionHeader(title: 'Best Sellers'),
            const SizedBox(height: AppConstants.spacing16),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ('Riz Blanc 25kg', 'Alimentation', 24, 76800.0),
                  ('Prestige Beer', 'Boissons', 144, 25920.0),
                  ('Huile Végétale 1L', 'Alimentation', 60, 36000.0),
                  ('Savon Dettol', 'Ménage', 45, 6750.0),
                  ('Coca-Cola 355ml', 'Boissons', 72, 8640.0),
                ].asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Text('${i + 1}', style: AppTextStyles.caption(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                                .copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.$1, style: AppTextStyles.body(color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
                              Text(p.$2, style: AppTextStyles.caption()),
                            ])),
                            Text('${p.$3} units', style: AppTextStyles.caption()),
                            const SizedBox(width: 12),
                            Text(CurrencyFormatter.local(context, p.$4), style: AppTextStyles.body(
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
            const SizedBox(height: AppConstants.spacing32),
            // Customer credit summary
            SectionHeader(title: 'Customer Credit Summary'),
            const SizedBox(height: AppConstants.spacing16),
            AppCard(
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Total Credit Extended', style: AppTextStyles.body()),
                    Text('HTG 375,000', style: AppTextStyles.price().copyWith(fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Total Outstanding', style: AppTextStyles.body()),
                    Text('HTG 97,700', style: AppTextStyles.price(color: AppColors.boldRed).copyWith(fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Customers with balance', style: AppTextStyles.body()),
                    Text('4 of 5', style: AppTextStyles.price().copyWith(fontSize: 13)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart(bool isDark) {
    final values = [28400.0, 35200.0, 42100.0, 38600.0, 51200.0, 48500.0, 4500.0];
    final gridColor = isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);
    final textColor = isDark ? AppColors.coolGray : AppColors.darkGray;

    return BarChart(BarChartData(
      gridData: FlGridData(drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          return Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(days[v.toInt()], style: AppTextStyles.caption(color: textColor).copyWith(fontSize: 9)));
        })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50,
            getTitlesWidget: (v, _) => Text(CurrencyFormatter.compact(v),
                style: AppTextStyles.caption(color: textColor).copyWith(fontSize: 9)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: values.asMap().entries.map((e) => BarChartGroupData(
        x: e.key,
        barRods: [BarChartRodData(
          toY: e.value,
          color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
          width: 28,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        )],
      )).toList(),
    ));
  }
}

Widget _KpiCard(String title, String value, String? change, bool isPositive) {
  return Builder(builder: (context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.caption()),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.price(color: isDark ? AppColors.warmWhite : AppColors.nearBlack).copyWith(fontSize: 16)),
          if (change != null) ...[
            const SizedBox(height: 4),
            Text(change, style: AppTextStyles.caption(color: isPositive ? AppColors.deepGreen : AppColors.darkGray)),
          ],
        ],
      ),
    );
  });
}

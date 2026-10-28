import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/focus_expand_search_row.dart';
import '../../core/widgets/app_card.dart';

class SalesHistory extends ConsumerStatefulWidget {
  const SalesHistory({super.key});

  @override
  ConsumerState<SalesHistory> createState() => _SalesHistoryState();
}

class _SalesHistoryState extends ConsumerState<SalesHistory> {
  String _searchText = '';
  String? _filterPayment;

  void _showFilterSheet(BuildContext context, bool isDark) {
    String? tempPayment = _filterPayment;
    showAppBottomSheet(
      context: context,
      child: StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: AppConstants.spacing24,
              right: AppConstants.spacing24,
              top: AppConstants.spacing24,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom + AppConstants.spacing24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filtrer les ventes',
                    style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack)),
                const SizedBox(height: AppConstants.spacing16),
                Text('Moyen de paiement', style: AppTextStyles.inputLabel()),
                const SizedBox(height: AppConstants.spacing8),
                Wrap(
                  spacing: 8,
                  children: ['Tous', 'MonCash', 'Espèces', 'Stripe', 'Crédit']
                      .map((m) => FilterChip(
                            label: Text(m),
                            selected: (m == 'Tous' && tempPayment == null) ||
                                tempPayment == m,
                            onSelected: (_) => setSheetState(
                                () => tempPayment = m == 'Tous' ? null : m),
                          ))
                      .toList(),
                ),
                const SizedBox(height: AppConstants.spacing24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheetState(() => tempPayment = null);
                        setState(() => _filterPayment = null);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Réinitialiser'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _filterPayment = tempPayment);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.nearBlack,
                      ),
                      child: const Text('Appliquer'),
                    ),
                  ),
                ]),
                const SizedBox(height: AppConstants.spacing8),
              ],
            ),
          ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(mockSalesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sales = allSales.where((s) {
      final matchSearch = _searchText.isEmpty ||
          s.cashier.toLowerCase().contains(_searchText.toLowerCase()) ||
          s.items.any(
              (i) => i.name.toLowerCase().contains(_searchText.toLowerCase()));
      final matchPayment =
          _filterPayment == null || s.paymentMethod == _filterPayment;
      return matchSearch && matchPayment;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historique des ventes',
                style: AppTextStyles.h1(
                  color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                )),
            const SizedBox(height: AppConstants.spacing16),
            // Filters
            FocusExpandSearchRow(
              search: TextField(
                onChanged: (v) => setState(() => _searchText = v),
                decoration: InputDecoration(
                  hintText: 'Rechercher des transactions...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput)),
                  filled: true,
                  fillColor:
                      isDark ? AppColors.darkSurface : AppColors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 12),
                ),
              ),
              trailing: [
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list_outlined),
                      onPressed: () => _showFilterSheet(context, isDark),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            isDark ? AppColors.darkSurface : AppColors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusButton)),
                      ),
                    ),
                    if (_filterPayment != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing16),
            Expanded(
              child: ListView.separated(
                itemCount: sales.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppConstants.spacing8),
                itemBuilder: (_, i) => _SaleCard(sale: sales[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final MockSale sale;
  const _SaleCard({required this.sale});

  Color get _methodColor {
    switch (sale.paymentMethod) {
      case 'MonCash':
        return AppColors.primaryBlue;
      case 'Espèces':
        return AppColors.deepGreen;
      case 'Stripe':
        return AppColors.statusMaintenance;
      default:
        return AppColors.darkGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr =
        '${sale.date.hour.toString().padLeft(2, '0')}:${sale.date.minute.toString().padLeft(2, '0')}';

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_outlined,
                color: AppColors.deepGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.items.map((i) => '${i.quantity}× ${i.name}').join(', '),
                  style: AppTextStyles.body(
                      color:
                          isDark ? AppColors.warmWhite : AppColors.nearBlack),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                    '${sale.cashier}${sale.customerName != null ? ' · ${sale.customerName}' : ''} · $timeStr',
                    style: AppTextStyles.caption()),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(CurrencyFormatter.local(context, sale.totalHtg),
                  style: AppTextStyles.price(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ).copyWith(fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _methodColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(sale.paymentMethod,
                    style: AppTextStyles.caption(color: _methodColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

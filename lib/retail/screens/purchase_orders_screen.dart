import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  String _statusFilter = 'Tous';

  void _showNewOrderSheet(
      BuildContext context, bool isDark, List<MockSupplier> suppliers) {
    MockSupplier? selectedSupplier =
        suppliers.isNotEmpty ? suppliers.first : null;
    final productCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final orderItems = <Map<String, String>>[];

    showAppBottomSheet(
      context: context,
      child: StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
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
                Text('Nouveau bon de commande',
                    style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack)),
                const SizedBox(height: AppConstants.spacing16),
                if (suppliers.isNotEmpty) ...[
                  DropdownButtonFormField<MockSupplier>(
                    value: selectedSupplier,
                    decoration: InputDecoration(
                      labelText: 'Supplier',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                      isDense: true,
                    ),
                    items: suppliers
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setSheet(() => selectedSupplier = v),
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                ],
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: productCtrl,
                      decoration: InputDecoration(
                        labelText: 'Product',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusInput)),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Qté',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusInput)),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: InputFormatters.digitsOnly,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: priceCtrl,
                      decoration: InputDecoration(
                        labelText: 'Prix HTG',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusInput)),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: InputFormatters.decimalAmount,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppColors.deepGreen),
                    onPressed: () {
                      if (productCtrl.text.trim().isEmpty) return;
                      setSheet(() {
                        orderItems.add({
                          'product': productCtrl.text.trim(),
                          'qty': qtyCtrl.text,
                          'price': priceCtrl.text,
                        });
                        productCtrl.clear();
                        qtyCtrl.text = '1';
                        priceCtrl.clear();
                      });
                    },
                  ),
                ]),
                if (orderItems.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  ...orderItems.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                                '${item['qty']}x ${item['product']} — ${item['price']} HTG',
                                style: AppTextStyles.caption()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 16, color: AppColors.boldRed),
                            onPressed: () =>
                                setSheet(() => orderItems.remove(item)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ]),
                      )),
                ],
                const SizedBox(height: AppConstants.spacing16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          orderItems.isEmpty ? null : () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.nearBlack,
                      ),
                      child: const Text('Créer un brouillon'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suppliers = ref.watch(mockSuppliersProvider);
    final allOrders = [
      ('PO-2026-045', 'DINASA', '20 févr. 2026', 'Partiellement reçu', 48000.0),
      ('PO-2026-044', 'Brasserie Nationale', '23 févr. 2026', 'Envoyé', 28800.0),
      (
        'PO-2026-043',
        'Importex Haïti',
        '18 févr. 2026',
        'Entièrement reçu',
        35600.0
      ),
      ('PO-2026-042', 'DINASA', '15 févr. 2026', 'Entièrement reçu', 62000.0),
      ('PO-2026-041', 'Importex Haïti', '10 févr. 2026', 'Brouillon', 18000.0),
    ];

    final orders = _statusFilter == 'Tous'
        ? allOrders
        : allOrders.where((o) {
            final s = o.$4;
            if (_statusFilter == 'Brouillon') return s == 'Brouillon';
            if (_statusFilter == 'Envoyé') return s == 'Envoyé';
            if (_statusFilter == 'Partiel') return s == 'Partiellement reçu';
            if (_statusFilter == 'Reçu') return s == 'Entièrement reçu';
            return true;
          }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('Bons de commande',
                        style: AppTextStyles.h1(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.primaryBlue,
                        ))),
                AppButton(
                  label: 'Nouvelle commande',
                  onPressed: () =>
                      _showNewOrderSheet(context, isDark, suppliers),
                  icon: Icons.add,
                  fullWidth: false,
                  width: 140,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Tous', 'Brouillon', 'Envoyé', 'Partiel', 'Reçu']
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(s),
                            selected: s == _statusFilter,
                            onSelected: (_) =>
                                setState(() => _statusFilter = s),
                            selectedColor: AppColors.primaryBlue,
                            labelStyle: AppTextStyles.caption(
                                color: s == _statusFilter
                                    ? AppColors.white
                                    : (isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),
            Expanded(
              child: ListView.separated(
                itemCount: orders.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppConstants.spacing8),
                itemBuilder: (_, i) {
                  final o = orders[i];
                  final statusType = o.$4 == 'Entièrement reçu'
                      ? StatusType.done
                      : o.$4 == 'Partiellement reçu' || o.$4 == 'Envoyé'
                          ? StatusType.inProgress
                          : StatusType.pending;
                  return AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(o.$1,
                                      style: AppTextStyles.body(
                                        color: isDark
                                            ? AppColors.warmWhite
                                            : AppColors.nearBlack,
                                      ).copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                      status: statusType,
                                      customLabel: o.$4,
                                      compact: true),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${o.$2} · ${o.$3}',
                                  style: AppTextStyles.caption()),
                            ],
                          ),
                        ),
                        Text(CurrencyFormatter.local(context, o.$5),
                            style: AppTextStyles.price(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack,
                            ).copyWith(fontSize: 13)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

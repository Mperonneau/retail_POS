import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_restaurant_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/input_formatters.dart';
import '../utils/date_formatter.dart';
import 'app_bottom_sheet.dart';
import 'app_button.dart';

/// Shows a bottom sheet listing items that are running low on stock.
/// [onItemTap] is called when user taps an item (e.g. to open item detail).
void showLowStockItemsSheet(
  BuildContext context,
  WidgetRef ref,
  List<MockInventoryItem> items, {
  void Function(MockInventoryItem)? onItemTap,
}) {
  if (items.isEmpty) return;
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    child: _LowStockItemsList(
      items: items,
      onItemTap: onItemTap,
    ),
  );
}

/// Shows inventory item details: balance, daily ledger (add/use per day), and adjustment.
/// [onEdit] is called when user taps Edit (e.g. to open add/edit sheet with existing item).
void showInventoryItemDetailSheet(
  BuildContext context,
  WidgetRef ref,
  MockInventoryItem item, {
  void Function(MockInventoryItem)? onEdit,
}) {
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    child: _InventoryItemDetailContent(item: item, onEdit: onEdit),
  );
}

void _showAddStockDialog(
    BuildContext context, WidgetRef ref, MockInventoryItem item) {
  final ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Add Stock — ${item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current: ${item.quantity} ${item.unit}',
              style: AppTextStyles.caption()),
          const SizedBox(height: AppConstants.spacing12),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: 'Quantity to add',
              suffixText: item.unit,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: InputFormatters.decimalAmount,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final add = double.tryParse(ctrl.text) ?? 0;
            if (add > 0) {
              ref.read(mockRestaurantInventoryProvider.notifier).addTransaction(
                    item.id,
                    InventoryTransactionType.add,
                    add,
                  );
            }
            Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void _showAdjustSheet(
    BuildContext context, WidgetRef ref, MockInventoryItem item) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController(text: 'Balance adjustment');
  bool isAdd = true;

  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    child: StatefulBuilder(
      builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppConstants.spacing24,
            right: AppConstants.spacing24,
            bottom: MediaQuery.of(context).viewInsets.bottom +
                AppConstants.spacing24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Adjustment',
                  style: AppTextStyles.h2(
                      color: isDark
                          ? AppColors.warmWhite
                          : AppColors.nearBlack)),
              const SizedBox(height: 8),
              Text(
                'Choose to add or subtract an amount from the balance.',
                style: AppTextStyles.caption(),
              ),
              const SizedBox(height: AppConstants.spacing24),
              Row(
                children: [
                  Expanded(
                    child: _AdjustmentOptionChip(
                      label: 'Add an amount',
                      icon: Icons.add_circle_outline,
                      isSelected: isAdd,
                      isDark: isDark,
                      onTap: () => setModalState(() => isAdd = true),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    child: _AdjustmentOptionChip(
                      label: 'Subtract an amount',
                      icon: Icons.remove_circle_outline,
                      isSelected: !isAdd,
                      isDark: isDark,
                      onTap: () => setModalState(() => isAdd = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing16),
              TextField(
                controller: amtCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: InputFormatters.decimalAmount,
                decoration: InputDecoration(
                  labelText: 'Amount (${item.unit})',
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBackground
                      : AppColors.warmOffWhite,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput)),
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: 'Reason / description',
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBackground
                      : AppColors.warmOffWhite,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput)),
                ),
              ),
              const SizedBox(height: AppConstants.spacing24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.buttonHeight / 2),
                        side: BorderSide(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      label: 'Apply Adjustment',
                      onPressed: () {
                        final amount = double.tryParse(amtCtrl.text) ?? 0;
                        if (amount <= 0) return;
                        final signedAmount = isAdd ? amount : -amount;
                        ref
                            .read(mockRestaurantInventoryProvider.notifier)
                            .addTransaction(
                              item.id,
                              InventoryTransactionType.adjust,
                              signedAmount,
                              note: noteCtrl.text.trim().isEmpty
                                  ? null
                                  : noteCtrl.text.trim(),
                            );
                        Navigator.pop(context);
                      },
                      icon: Icons.tune_outlined,
                      fullWidth: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AdjustmentOptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _AdjustmentOptionChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spacing12,
              horizontal: AppConstants.spacing12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.skyBlue.withValues(alpha: 0.2)
                    : AppColors.primaryBlue.withValues(alpha: 0.12))
                : (isDark ? AppColors.darkBackground : AppColors.warmOffWhite),
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            border: Border.all(
              color: isSelected
                  ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                  : (isDark ? AppColors.coolGray : AppColors.darkGray)
                      .withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body(
                    color: isSelected
                        ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                        : (isDark ? AppColors.warmWhite : AppColors.nearBlack),
                  ).copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryItemDetailContent extends ConsumerStatefulWidget {
  final MockInventoryItem item;
  final void Function(MockInventoryItem)? onEdit;

  const _InventoryItemDetailContent({
    required this.item,
    this.onEdit,
  });

  @override
  ConsumerState<_InventoryItemDetailContent> createState() =>
      _InventoryItemDetailContentState();
}

class _InventoryItemDetailContentState
    extends ConsumerState<_InventoryItemDetailContent> {
  static const int _initialDaysCount = 7;
  int _daysShown = _initialDaysCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = ref.watch(mockRestaurantInventoryProvider);
    final currentItem = items.where((i) => i.id == widget.item.id).firstOrNull ?? widget.item;
    final notifier = ref.read(mockRestaurantInventoryProvider.notifier);
    final allSummaries = notifier.getDailySummaries(currentItem.id);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final todaySummary = allSummaries.where((s) => s.date == todayDate).firstOrNull;
    final totalAddToday = todaySummary?.totalAdd ?? 0;
    final totalUseToday = todaySummary?.totalUse ?? 0;

    final displayedSummaries = allSummaries.take(_daysShown).toList();
    final hasMore = _daysShown < allSummaries.length;

    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentItem.name,
              style: AppTextStyles.h2(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
            Text(currentItem.category, style: AppTextStyles.caption()),
            const SizedBox(height: AppConstants.spacing24),
            // Balance / Add / Use today
            Row(
              children: [
                _StatCard(
                  label: 'Total Balance',
                  value: '${currentItem.quantity.toStringAsFixed(currentItem.quantity == currentItem.quantity.truncate() ? 0 : 1)} ${currentItem.unit}',
                  isDark: isDark,
                ),
                const SizedBox(width: AppConstants.spacing12),
                _StatCard(
                  label: 'Added Today',
                  value: '${totalAddToday.toStringAsFixed(0)} ${currentItem.unit}',
                  isDark: isDark,
                  valueColor: AppColors.deepGreen,
                ),
                const SizedBox(width: AppConstants.spacing12),
                _StatCard(
                  label: 'Used Today',
                  value: '${totalUseToday.toStringAsFixed(0)} ${currentItem.unit}',
                  isDark: isDark,
                  valueColor: AppColors.boldRed,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing24),
            // Daily ledger
            Text(
              'Daily Ledger',
              style: AppTextStyles.h3(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
            const SizedBox(height: AppConstants.spacing12),
            if (allSummaries.isEmpty)
              Text(
                'No transactions yet.',
                style: AppTextStyles.caption(),
              )
            else ...[
              // Table header
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Date',
                      style: AppTextStyles.caption().copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      'Added',
                      style: AppTextStyles.caption().copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      'Used',
                      style: AppTextStyles.caption().copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      'Balance',
                      style: AppTextStyles.caption().copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
              ...displayedSummaries.map((s) {
                final isToday = s.date == todayDate;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spacing4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          isToday ? 'Today' : DateFormatter.shortDate(s.date),
                          style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '+${s.totalAdd.toStringAsFixed(0)}',
                          style: AppTextStyles.caption(color: AppColors.deepGreen),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '-${s.totalUse.toStringAsFixed(0)}',
                          style: AppTextStyles.caption(color: AppColors.boldRed),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          '${s.balance.toStringAsFixed(0)} ${currentItem.unit}',
                          style: AppTextStyles.body(
                              color: isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: AppConstants.spacing8),
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _daysShown += _initialDaysCount),
                    child: const Text('Load more'),
                  ),
                ),
            ],
            const SizedBox(height: AppConstants.spacing24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Add Stock',
                    onPressed: () =>
                        _showAddStockDialog(context, ref, currentItem),
                    icon: Icons.add,
                    variant: AppButtonVariant.secondary,
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                if (widget.onEdit != null) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Edit Item',
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEdit!(currentItem);
                      },
                      icon: Icons.edit_outlined,
                      variant: AppButtonVariant.secondary,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                ],
                Expanded(
                  child: AppButton(
                    label: 'Adjust Stock',
                    onPressed: () => _showAdjustSheet(context, ref, currentItem),
                    icon: Icons.tune,
                    variant: AppButtonVariant.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing8),
          ],
        ),
      ),
    );
  }
}

class _LowStockItemsList extends StatelessWidget {
  final List<MockInventoryItem> items;
  final void Function(MockInventoryItem)? onItemTap;

  const _LowStockItemsList({
    required this.items,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing24,
        0,
        AppConstants.spacing24,
        AppConstants.spacing24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items running low on stock',
            style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
          ),
          const SizedBox(height: AppConstants.spacing16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppConstants.spacing8),
              itemBuilder: (context, i) {
                final item = items[i];
                return InkWell(
                  onTap: onItemTap != null
                      ? () {
                          Navigator.pop(context);
                          onItemTap!(item);
                        }
                      : null,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusCard),
                  child: Container(
                    padding: const EdgeInsets.all(AppConstants.spacing12),
                    decoration: BoxDecoration(
                      color: AppColors.boldRed.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusCard),
                      border: Border.all(
                          color: AppColors.boldRed.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.boldRed, size: 20),
                        const SizedBox(width: AppConstants.spacing12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.warmWhite
                                      : AppColors.nearBlack,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncate() ? 0 : 1)} ${item.unit} / min ${item.minThreshold.toStringAsFixed(0)} ${item.unit}',
                                style: AppTextStyles.caption(
                                    color: AppColors.boldRed),
                              ),
                            ],
                          ),
                        ),
                        if (onItemTap != null)
                          Icon(Icons.chevron_right_rounded,
                              size: 18,
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : AppColors.lightBlue.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption()),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.body(
                color: valueColor ??
                    (isDark ? AppColors.warmWhite : AppColors.nearBlack),
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

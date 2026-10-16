import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../mock/mock_hotel_data.dart';
import '../mock/mock_restaurant_data.dart';
import '../providers/app_notification_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'discount_approval_dialog.dart';
import 'store_credit_recipient_picker.dart';

enum ApplyStoreCreditBillKind { restaurant, hotelRestaurant }

/// Picks a customer profile that can receive issued store credit (prepaid refund).
Future<String?> pickCustomerForStoreCreditIssue(
  BuildContext context,
  WidgetRef _, {
  required bool isDark,
}) async {
  return showStoreCreditRecipientPicker(
    context,
    isDark: isDark,
  );
}

Future<void> showApplyStoreCreditForBill(
  BuildContext context,
  WidgetRef ref, {
  required bool isDark,
  required int orderId,
  required double maxApplyHtg,
  required ApplyStoreCreditBillKind billKind,
}) async {
  final approved = await showAdminApprovalDialog(
    context,
    ref,
    message:
        'Applying store credit to this bill requires manager authorization.',
    isDark: isDark,
    title: 'Admin authorization',
  );
  if (approved != true || !context.mounted) return;
  if (maxApplyHtg <= 0.009) {
    ref.read(appNotificationProvider.notifier).show(
          'No remaining balance to cover with store credit.',
          kind: AppNotificationKind.info,
        );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ApplyStoreCreditSheetBody(
        isDark: isDark,
        orderId: orderId,
        maxApplyHtg: maxApplyHtg,
        billKind: billKind,
      ),
    ),
  );
}

class _ApplyStoreCreditSheetBody extends ConsumerStatefulWidget {
  final bool isDark;
  final int orderId;
  final double maxApplyHtg;
  final ApplyStoreCreditBillKind billKind;

  const _ApplyStoreCreditSheetBody({
    required this.isDark,
    required this.orderId,
    required this.maxApplyHtg,
    required this.billKind,
  });

  @override
  ConsumerState<_ApplyStoreCreditSheetBody> createState() =>
      _ApplyStoreCreditSheetBodyState();
}

class _ApplyStoreCreditSheetBodyState
    extends ConsumerState<_ApplyStoreCreditSheetBody> {
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  Customer? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Iterable<Customer> _eligible(CustomerState state) sync* {
    for (final c in state.customers) {
      if (!c.hasStoreCreditIdentity) continue;
      final bal = state.storeCreditBalanceFor(c.id);
      if (bal <= 0.009) continue;
      yield c;
    }
  }

  List<Customer> _filtered(CustomerState state) {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = _eligible(state).toList();
    if (q.isEmpty) return list;
    list = list.where((c) {
      final blob =
          '${c.displayFirstLastName} ${c.name} ${c.phone}'.toLowerCase();
      return blob.contains(q);
    }).toList();
    return list;
  }

  void _apply(Customer c) {
    final v = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) return;
    final state = ref.read(customerProvider);
    final available = state.storeCreditBalanceFor(c.id);
    final use = math.min(v, math.min(widget.maxApplyHtg, available));
    if (use <= 0.009) return;

    ref.read(customerProvider.notifier).redeemStoreCredit(
          customerId: c.id,
          amountHtg: use,
          description: 'Applied to Order #${widget.orderId}',
          orderId: '${widget.orderId}',
        );
    switch (widget.billKind) {
      case ApplyStoreCreditBillKind.restaurant:
        ref
            .read(mockRestaurantOrdersProvider.notifier)
            .applyCustomerCredit(widget.orderId, use);
        break;
      case ApplyStoreCreditBillKind.hotelRestaurant:
        ref
            .read(mockHotelRestaurantOrdersProvider.notifier)
            .applyCustomerCredit(widget.orderId, use);
        break;
    }
    ref.read(appNotificationProvider.notifier).show(
          'Store credit applied to Order #${widget.orderId}',
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final state = ref.watch(customerProvider);
    final customers = _filtered(state);
    final primary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final secondary = isDark ? AppColors.coolGray : AppColors.darkGray;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Apply store credit',
                    style: AppTextStyles.h3(color: primary),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: secondary,
                ),
              ],
            ),
            Text(
              'Order #${widget.orderId} · up to ${CurrencyFormatter.local(context, widget.maxApplyHtg)}',
              style: AppTextStyles.caption(color: secondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Find customer',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusInput),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (customers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No customers with store credit balance and complete ID on file.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(color: secondary),
                  ),
                ),
              )
            else
              SizedBox(
                height: 260,
                child: ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: secondary.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (_, i) {
                    final c = customers[i];
                    final bal = state.storeCreditBalanceFor(c.id);
                    final sel = _selected?.id == c.id;
                    return InkWell(
                      onTap: () => setState(() {
                        _selected = c;
                        _amountCtrl.text = math
                            .min(bal, widget.maxApplyHtg)
                            .toStringAsFixed(0);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              sel
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 18,
                              color: sel
                                  ? AppColors.deepGreen
                                  : secondary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.displayFirstLastName,
                                    style: AppTextStyles.body(color: primary)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    c.phone,
                                    style: AppTextStyles.caption(
                                        color: secondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              CurrencyFormatter.local(context, bal),
                              style: AppTextStyles.body(color: AppColors.deepGreen)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount to apply (HTG)',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _apply(_selected!),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.deepGreen,
                    foregroundColor: AppColors.white,
                  ),
                  child: const Text('Apply to bill'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

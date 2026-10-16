import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

/// Bottom strip when staging items on an existing order (restaurant + hotel restaurant).
/// Uses a two-row layout on narrow widths to avoid horizontal overflow.
class StagedOrderBottomBar extends StatelessWidget {
  final int stagedCount;
  final double subtotal;
  final VoidCallback onView;
  final VoidCallback onConfirm;
  final VoidCallback onClear;

  const StagedOrderBottomBar({
    super.key,
    required this.stagedCount,
    required this.subtotal,
    required this.onView,
    required this.onConfirm,
    required this.onClear,
  });

  static const _barBg = AppColors.sidebarBackground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _barBg,
      elevation: 8,
      shadowColor: Colors.black38,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide single-row layout needs ~1100px; typical split POS views use two rows.
            final compact = constraints.maxWidth < 1100;
            final chip = _StagedChip(count: stagedCount);
            final viewBtn = OutlinedButton.icon(
              onPressed: onView,
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text('View'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: AppTextStyles.button(color: AppColors.white)
                    .copyWith(fontSize: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            final cancelBtn = TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.coralRed,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: AppTextStyles.button(color: AppColors.white)
                    .copyWith(fontSize: 12),
              ),
              child: const Text('Cancel'),
            );
            final addBtn = FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Add to Order'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: AppColors.nearBlack,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: AppTextStyles.button(color: AppColors.nearBlack),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );

            final priceText = Text(
              CurrencyFormatter.local(context, subtotal),
              style: AppTextStyles.price(color: AppColors.white),
              overflow: TextOverflow.ellipsis,
            );

            final padding = const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
              vertical: AppConstants.spacing8,
            );

            if (compact) {
              return Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(child: chip),
                        const SizedBox(width: AppConstants.spacing8),
                        viewBtn,
                        const SizedBox(width: AppConstants.spacing8),
                        cancelBtn,
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Subtotal',
                                style: AppTextStyles.caption(
                                  color: AppColors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              priceText,
                            ],
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacing8),
                        Flexible(
                          flex: 2,
                          child: addBtn,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: padding,
              child: Row(
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: chip,
                  ),
                  const SizedBox(width: AppConstants.spacing8),
                  viewBtn,
                  const SizedBox(width: AppConstants.spacing8),
                  cancelBtn,
                  const Spacer(),
                  Text(
                    'Subtotal',
                    style: AppTextStyles.caption(
                      color: AppColors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing8),
                  Flexible(
                    child: priceText,
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  addBtn,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StagedChip extends StatelessWidget {
  final int count;

  const _StagedChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_basket_outlined,
              size: 13, color: AppColors.amber),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$count item${count > 1 ? 's' : ''} staged',
              style: AppTextStyles.caption(color: AppColors.amber)
                  .copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

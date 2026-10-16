import 'package:flutter/material.dart';

import '../mock/mock_restaurant_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

/// POS grid tile for ordering: shows price, qty controls, and blocked state when unavailable.
///
/// Tapping anywhere on the card (except **−**) adds one unit, matching classic POS behavior.
class OrderMenuItemTile extends StatelessWidget {
  final MockMenuItem item;
  final int cartQty;
  final bool canAddMore;
  final String? blockedHint;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const OrderMenuItemTile({
    super.key,
    required this.item,
    required this.cartQty,
    required this.canAddMore,
    this.blockedHint,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isInCart = cartQty > 0;
    final blocked = !canAddMore;
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final showBadge =
        blocked && blockedHint != null && blockedHint!.isNotEmpty;

    final card = AnimatedContainer(
      duration: AppConstants.animFast,
      decoration: BoxDecoration(
        color: isInCart
            ? (isDark
                ? AppColors.primaryBlue.withValues(alpha: 0.2)
                : AppColors.lightBlue)
            : (isDark ? AppColors.darkSurface : AppColors.white),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(
          color: blocked
              ? AppColors.boldRed.withValues(alpha: 0.35)
              : (isInCart
                  ? AppColors.primaryBlue.withValues(alpha: 0.4)
                  : (isDark
                      ? AppColors.coolGray.withValues(alpha: 0.25)
                      : AppColors.coolGray.withValues(alpha: 0.35))),
          width: blocked ? 1.5 : 1,
        ),
        boxShadow: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing12),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 2,
                      right: showBadge ? 58 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              item.name,
                              style: AppTextStyles.caption(
                                color: blocked
                                    ? (isDark
                                        ? AppColors.coolGray
                                        : AppColors.darkGray)
                                    : (isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack),
                              ).copyWith(fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.local(context, item.priceHtg),
                          style: AppTextStyles.caption(
                            color: blocked
                                ? (isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray)
                                : primary,
                          ).copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (cartQty > 0) ...[
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onRemove,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.boldRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.remove,
                                size: 16, color: AppColors.boldRed),
                          ),
                        ),
                      ),
                      Text(
                        '$cartQty',
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ] else
                      const SizedBox(width: 30, height: 30),
                    // + control: no separate tap target — whole-card [onAdd] handles it
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: blocked
                            ? (isDark
                                ? AppColors.coolGray.withValues(alpha: 0.35)
                                : AppColors.coolGray.withValues(alpha: 0.25))
                            : AppColors.amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 16,
                        color: blocked
                            ? (isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.5)
                                : AppColors.nearBlack
                                    .withValues(alpha: 0.35))
                            : AppColors.nearBlack,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (showBadge)
              Positioned(
                top: 0,
                right: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.boldRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.boldRed.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      blockedHint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTextStyles.caption(color: AppColors.boldRed)
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 9,
                            height: 1.1,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: blocked ? 0.88 : 1,
      child: Semantics(
        button: true,
        label:
            '${item.name}, ${CurrencyFormatter.local(context, item.priceHtg)}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAdd,
            child: card,
          ),
        ),
      ),
    );
  }
}

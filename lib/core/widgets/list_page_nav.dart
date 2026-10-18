import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Plain mobile page control: chevron, "current / total", chevron.
/// Sits in the list scroll. No page chips and no bar.
class ListPageNav extends StatelessWidget {
  const ListPageNav({
    super.key,
    required this.isDark,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isDark;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final disabled = isDark ? AppColors.coolGray : AppColors.darkGray;
    final active = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Page précédente',
          onPressed: onPrevious,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(
            minWidth: AppConstants.minTouchTarget,
            minHeight: AppConstants.minTouchTarget,
          ),
          icon: Icon(
            Icons.chevron_left_rounded,
            color: onPrevious == null ? disabled : active,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '$currentPage / $totalPages',
            style: AppTextStyles.caption(
              color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Page suivante',
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(
            minWidth: AppConstants.minTouchTarget,
            minHeight: AppConstants.minTouchTarget,
          ),
          icon: Icon(
            Icons.chevron_right_rounded,
            color: onNext == null ? disabled : active,
          ),
        ),
      ],
    );
  }
}

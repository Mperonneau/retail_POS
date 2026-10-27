import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';

const _kAllCategories = '__all_categories__';

/// Category filter used on the suppliers, products, and inventory lists.
///
/// A chosen category clears from a circle at the end of the field.
class CategoryFilterButton extends StatelessWidget {
  const CategoryFilterButton({
    super.key,
    required this.isDark,
    required this.fill,
    required this.borderColor,
    required this.label,
    required this.selected,
    required this.categories,
    required this.onChanged,
    this.expand = false,
  });

  final bool isDark;
  final Color fill;
  final Color borderColor;
  final String label;
  final String? selected;
  final List<String> categories;
  final ValueChanged<String?> onChanged;
  final bool expand;

  bool get _active => selected != null;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primaryBlue;
    final bg = _active
        ? activeColor.withValues(alpha: isDark ? 0.25 : 0.08)
        : fill;
    final border = _active
        ? activeColor.withValues(alpha: isDark ? 0.55 : 0.4)
        : borderColor;
    final textColor = _active
        ? (isDark ? AppColors.skyBlue : activeColor)
        : (isDark ? AppColors.coolGray : AppColors.darkGray);

    final labelStyle = AppTextStyles.caption(
      color: textColor,
    ).copyWith(fontWeight: _active ? FontWeight.w600 : FontWeight.w500);
    final field = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.category_outlined, size: 16, color: textColor),
        const SizedBox(width: 6),
        if (expand)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          )
        else
          Text(label, style: labelStyle),
        const SizedBox(width: 4),
        Icon(Icons.expand_more_rounded, size: 16, color: textColor),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(14, 6, _active ? 6 : 14, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expand)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _openMenu(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: field,
                ),
              ),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openMenu(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: field,
              ),
            ),
          if (_active) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Effacer la catégorie',
              child: Material(
                color: isDark ? AppColors.darkBackground : AppColors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(null),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                                .withValues(alpha: 0.55),
                      ),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openMenu(BuildContext context) {
    final items = <PopupMenuEntry<String?>>[
      PopupMenuItem<String?>(
        value: _kAllCategories,
        child: Row(
          children: [
            Icon(
              Icons.select_all_rounded,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Toutes les catégories',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 4),
      ...categories.map(
        (c) => PopupMenuItem<String?>(
          value: c,
          child: Row(
            children: [
              Icon(
                c == selected ? Icons.check_rounded : Icons.category_outlined,
                size: 16,
                color: c == selected
                    ? AppColors.primaryBlue
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTextStyles.body(
                        color: c == selected
                            ? (isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue)
                            : (isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack),
                      ).copyWith(
                        fontWeight: c == selected ? FontWeight.w600 : null,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String?>(
      context: context,
      color: isDark ? AppColors.darkSurface : AppColors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        side: BorderSide(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.darkGray.withValues(alpha: 0.15),
        ),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: items,
    ).then((val) {
      if (val == null) return;
      onChanged(val == _kAllCategories ? null : val);
    });
  }
}

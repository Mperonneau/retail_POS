import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Category chips + search on one row (wide) or stacked (narrow).
/// Uses a compact bar height so chips and search align without overlapping.
class MenuFilterSearchBar extends StatelessWidget {
  const MenuFilterSearchBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchQuery,
    this.hintText = 'Rechercher dans le menu…',
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchQuery;
  final String hintText;

  static const double _barHeight = AppConstants.buttonHeightCompact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.darkSurface : AppColors.white;

    final searchField = SizedBox(
      height: _barHeight,
      child: TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        style: AppTextStyles.body(
          color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
        ).copyWith(fontSize: 13, height: 1.2),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            maxHeight: _barHeight,
            minHeight: _barHeight,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: _barHeight,
                    maxHeight: _barHeight,
                  ),
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    searchController.clear();
                    onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            borderSide: BorderSide(
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              width: 2,
            ),
          ),
        ),
      ),
    );

    final chips = categories.map((c) {
      final isActive = selectedCategory == c;
      return Padding(
        padding: const EdgeInsets.only(right: AppConstants.spacing8),
        child: FilterChip(
          label: Text(c),
          selected: isActive,
          onSelected: (_) => onCategorySelected(c),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selectedColor: AppColors.amber.withValues(alpha: 0.35),
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.warmOffWhite,
          side: BorderSide(
            color: isActive
                ? AppColors.amber
                : (isDark ? AppColors.darkBorder : const Color(0xFFCCCCCC)),
          ),
          labelStyle: AppTextStyles.caption(
            color: isActive
                ? AppColors.nearBlack
                : (isDark ? AppColors.warmWhite : AppColors.darkGray),
          ).copyWith(fontWeight: isActive ? FontWeight.w600 : FontWeight.w400),
        ),
      );
    }).toList();

    final filterScroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: chips,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < AppConstants.mobileBreakpoint;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _barHeight,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: filterScroll,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
              searchField,
            ],
          );
        }
        // Wide: strict split — filters scroll inside left half, search never draws over chips.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 1,
              child: SizedBox(
                height: _barHeight,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: filterScroll,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacing12),
            Expanded(
              flex: 1,
              child: ClipRect(child: searchField),
            ),
          ],
        );
      },
    );
  }
}

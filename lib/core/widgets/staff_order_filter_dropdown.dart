import 'package:flutter/material.dart';

import '../models/staff_directory_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Orders filter: [activeStaff] only (exclude deactivated). `null` = all staff.
/// Styled to match the orders search [TextField] (36px tall, pill border).
class StaffOrderFilterDropdown extends StatelessWidget {
  final bool isDark;
  final List<StaffDirectoryEntry> activeStaff;
  final String? selectedStaffId;
  final ValueChanged<String?> onChanged;

  const StaffOrderFilterDropdown({
    super.key,
    required this.isDark,
    required this.activeStaff,
    required this.selectedStaffId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final borderSide = BorderSide(color: primary.withValues(alpha: 0.25));
    final validId = selectedStaffId != null &&
            activeStaff.any((e) => e.id == selectedStaffId)
        ? selectedStaffId
        : null;

    return SizedBox(
      height: 36,
      child: Theme(
        data: Theme.of(context).copyWith(
          visualDensity: VisualDensity.compact,
          hoverColor: Colors.transparent,
        ),
        child: InputDecorator(
          isFocused: false,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 0,
            ),
            prefixIcon: Icon(
              Icons.person_outline,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.primaryBlue,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: borderSide,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: primary),
            ),
            isDense: true,
            filled: true,
            fillColor: isDark ? AppColors.darkSurface : AppColors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: validId,
              isDense: true,
              isExpanded: true,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.arrow_drop_down, size: 18, color: primary),
              style: AppTextStyles.caption(),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All staff', style: AppTextStyles.caption()),
                ),
                ...activeStaff.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(
                      s.fullName,
                      style: AppTextStyles.caption(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              selectedItemBuilder: (context) {
                return [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'All staff',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ),
                  ...activeStaff.map(
                    (s) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(),
                      ),
                    ),
                  ),
                ];
              },
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

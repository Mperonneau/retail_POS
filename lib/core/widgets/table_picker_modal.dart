import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_restaurant_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Shows a dialog for picking an available table.
/// Returns the selected table, or `null` if cancelled.
Future<MockTable?> showTablePickerModal(
  BuildContext context,
  WidgetRef ref, {
  bool useRootNavigator = true,
}) async {
  final tables = ref.read(mockTablesProvider);
  final available = tables.where((t) => t.status == 'available').toList();
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showDialog<MockTable>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final surfaceBg = isDark ? AppColors.darkSurface : AppColors.white;
      final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
      final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

      return AlertDialog(
        backgroundColor: surfaceBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        contentPadding: EdgeInsets.zero,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.table_restaurant, size: 22, color: AppColors.amber),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign table',
                        style: AppTextStyles.h2(
                            color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
                      ),
                      Text(
                        '${available.length} table${available.length != 1 ? 's' : ''} available',
                        style: AppTextStyles.caption(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(
                height: 1,
                color: isDark ? AppColors.darkBackground : const Color(0xFFEEEEEE),
              ),
              const SizedBox(height: AppConstants.spacing12),
              available.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacing24, vertical: AppConstants.spacing24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            size: 40,
                            color: isDark ? AppColors.coolGray : AppColors.darkGray,
                          ),
                          const SizedBox(height: AppConstants.spacing12),
                          Text(
                            'No tables available',
                            style: AppTextStyles.body(color: muted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.spacing16,
                          0,
                          AppConstants.spacing16,
                          AppConstants.spacing12,
                        ),
                        child: Wrap(
                          spacing: AppConstants.spacing8,
                          runSpacing: AppConstants.spacing8,
                          children: [
                            for (final t in available)
                              _TablePickTile(
                                table: t,
                                isDark: isDark,
                                primary: primary,
                                onTap: () => Navigator.pop(ctx, t),
                              ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: muted,
            ),
            child: Text('Cancel', style: AppTextStyles.button(color: muted)),
          ),
        ],
      );
    },
  );
}

class _TablePickTile extends StatelessWidget {
  final MockTable table;
  final bool isDark;
  final Color primary;
  final VoidCallback onTap;

  const _TablePickTile({
    required this.table,
    required this.isDark,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        width: 100,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : const Color(0xFFDDDDDD),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            highlightColor: primary.withValues(alpha: 0.08),
            splashColor: primary.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing12, vertical: AppConstants.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.deepGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.table_restaurant,
                      size: 20,
                      color: AppColors.deepGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    table.name,
                    style: AppTextStyles.body(color: textPrimary)
                        .copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${table.capacity} seats',
                    style: AppTextStyles.caption(color: muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.deepGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.deepGreen.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Available',
                      style: AppTextStyles.caption(color: AppColors.deepGreen)
                          .copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

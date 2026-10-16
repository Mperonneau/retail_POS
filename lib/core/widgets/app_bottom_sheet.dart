import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/constants.dart';

/// Opens a theme-aware modal bottom sheet pre-wrapped in [AppBottomSheet].
/// Use this instead of calling [showModalBottomSheet] directly so that
/// background color, shape, and the drag handle are always consistent.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = true,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    // false: keep the sheet on the same navigator as GoRouter pages. Using the
    // root navigator + deferred pop can pop a route page instead of the sheet on web.
    useRootNavigator: false,
    isScrollControlled: isScrollControlled,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AppBottomSheet(child: child),
  );
}

/// Wraps bottom sheet content with a drag handle and close button.
/// Use as the root widget inside [showModalBottomSheet]'s builder.
/// The [child] should include its own padding (e.g. for bottom viewInsets).
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final handleColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppConstants.spacing24,
                right: AppConstants.spacing8,
                top: AppConstants.spacing12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: handleColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 22,
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                    onPressed: () {
                      if (!context.mounted) return;
                      Navigator.maybePop(context);
                    },
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Expanded(
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

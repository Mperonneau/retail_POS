import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';

import 'widgets.dart';

/// Opaque page change. The previous screen stays covered, and a spinner
/// shows until the new page has faded in.
Page<void> storePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value;
          final appear = const Interval(
            0.35,
            1,
            curve: Curves.easeOut,
          ).transform(t);
          return ColoredBox(
            color: AppColors.warmOffWhite,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (appear < 1)
                  Center(
                    child: Opacity(
                      opacity: (1 - appear).clamp(0, 1),
                      child: const AppSpinner(),
                    ),
                  ),
                Opacity(opacity: appear, child: child),
              ],
            ),
          );
        },
      );
    },
  );
}

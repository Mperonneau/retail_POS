import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Scroll behavior that shows the vertical scrollbar thumb and track at all
/// times when the layout is desktop-sized (width >= [AppConstants.tabletBreakpoint]).
/// Other layouts keep the default platform behavior.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    switch (axisDirectionToAxis(details.direction)) {
      case Axis.horizontal:
        return child;
      case Axis.vertical:
        final isDesktop = MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
        if (isDesktop) {
          return Scrollbar(
            controller: details.controller,
            thumbVisibility: true,
            trackVisibility: true,
            child: child,
          );
        }
        return super.buildScrollbar(context, child, details);
    }
  }
}

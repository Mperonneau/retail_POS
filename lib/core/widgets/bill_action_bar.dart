import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Lays out bill-footer action buttons in rows of two with tight spacing.
///
/// When there is a single action it stretches full width.
/// Two or more actions are chunked into pairs — last odd button sits alone.
class BillActionBar extends StatelessWidget {
  final List<Widget> actions;

  const BillActionBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      if (i + 1 < actions.length) {
        rows.add(Row(
          children: [
            Expanded(child: actions[i]),
            const SizedBox(width: AppConstants.spacing8),
            Expanded(child: actions[i + 1]),
          ],
        ));
      } else {
        rows.add(actions[i]);
      }
      if (i + 2 < actions.length) {
        rows.add(const SizedBox(height: AppConstants.spacing4));
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        AppConstants.spacing4,
        AppConstants.spacing16,
        AppConstants.spacing8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}

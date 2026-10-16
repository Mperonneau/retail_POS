import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Stacks [children] in rows of two equal-width actions (e.g. table bottom sheet).
class TableSheetActionGrid extends StatelessWidget {
  final List<Widget> children;

  const TableSheetActionGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final left = children[i];
      final right = i + 1 < children.length ? children[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            if (right != null) ...[
              const SizedBox(width: AppConstants.spacing8),
              Expanded(child: right),
            ],
          ],
        ),
      );
      if (i + 2 < children.length) {
        rows.add(const SizedBox(height: AppConstants.spacing8));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

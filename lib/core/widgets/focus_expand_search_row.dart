import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A search field that shares a row with other controls.
///
/// On a phone, focusing the field collapses those controls so the field uses
/// the full row. Losing focus restores the row.
class FocusExpandSearchRow extends StatefulWidget {
  const FocusExpandSearchRow({
    super.key,
    required this.search,
    this.leading = const [],
    this.trailing = const [],
    this.gap = 8,
    this.onlyWhenNarrow = true,
  });

  final Widget search;
  final List<Widget> leading;
  final List<Widget> trailing;
  final double gap;

  /// When true, the row only expands on viewports narrower than
  /// [AppConstants.mobileBreakpoint]. Wider layouts keep every control visible.
  final bool onlyWhenNarrow;

  @override
  State<FocusExpandSearchRow> createState() => _FocusExpandSearchRowState();
}

class _FocusExpandSearchRowState extends State<FocusExpandSearchRow> {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'focus-expand-search',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  /// Update after the focus event. setState inside the listener rebuilds the
  /// field and drops the focus that was just gained.
  void _onFocus() {
    final focused = _focusNode.hasFocus;
    scheduleMicrotask(() {
      if (!mounted || focused == _focused) return;
      setState(() => _focused = focused);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < AppConstants.mobileBreakpoint;
        final collapse = _focused && (!widget.onlyWhenNarrow || narrow);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final child in widget.leading)
              _CollapsibleSlot(
                collapse: collapse,
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.only(right: widget.gap),
                child: child,
              ),
            Expanded(
              child: Focus(focusNode: _focusNode, child: widget.search),
            ),
            for (final child in widget.trailing)
              _CollapsibleSlot(
                collapse: collapse,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(left: widget.gap),
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _CollapsibleSlot extends StatelessWidget {
  const _CollapsibleSlot({
    required this.collapse,
    required this.alignment,
    required this.padding,
    required this.child,
  });

  final bool collapse;
  final Alignment alignment;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: collapse,
      child: AnimatedSize(
        duration: AppConstants.animFast,
        curve: Curves.easeOut,
        alignment: alignment,
        child: collapse
            ? const SizedBox.shrink()
            : Padding(padding: padding, child: child),
      ),
    );
  }
}

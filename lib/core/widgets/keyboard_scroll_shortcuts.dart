import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps its [child] in a focusable area that captures arrow / page / home /
/// end keys and scrolls the first vertical [Scrollable] found in the subtree.
///
/// A [Listener] requests focus on pointer down so clicking anywhere in the
/// content area enables keyboard scrolling without competing with child
/// [InkWell] / [GestureDetector] taps (e.g. on web, a parent [GestureDetector]
/// can win the gesture arena and swallow list row taps). When focus is inside
/// an [EditableText] (e.g. a [TextField]), keys are passed through unchanged.
class KeyboardScrollArea extends StatefulWidget {
  const KeyboardScrollArea({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardScrollArea> createState() => _KeyboardScrollAreaState();
}

class _KeyboardScrollAreaState extends State<KeyboardScrollArea> {
  final FocusNode _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  ScrollableState? _findVerticalScrollable() {
    ScrollableState? result;
    void visitor(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        if (axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical) {
          result = scrollable;
          return;
        }
      }
      element.visitChildren(visitor);
    }
    (context as Element).visitChildren(visitor);
    return result;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Don't steal keys from text fields.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }

    final scrollable = _findVerticalScrollable();
    if (scrollable == null) return KeyEventResult.ignored;

    final position = scrollable.position;

    double? target;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        target = position.pixels + 40;
      case LogicalKeyboardKey.arrowUp:
        target = position.pixels - 40;
      case LogicalKeyboardKey.pageDown:
        target = position.pixels + position.viewportDimension;
      case LogicalKeyboardKey.pageUp:
        target = position.pixels - position.viewportDimension;
      case LogicalKeyboardKey.end:
        target = position.maxScrollExtent;
      case LogicalKeyboardKey.home:
        target = position.minScrollExtent;
      default:
        return KeyEventResult.ignored;
    }

    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return KeyEventResult.handled;

    position.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: widget.child,
      ),
    );
  }
}

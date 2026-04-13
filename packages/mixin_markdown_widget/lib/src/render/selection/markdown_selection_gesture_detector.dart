import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/document.dart';
import '../../selection/selection_controller.dart';

typedef MarkdownHitTestPositionCallback = DocumentPosition? Function(
  Offset globalPosition, {
  required bool clamp,
});
typedef MarkdownHitTestExactTextPositionCallback = DocumentPosition? Function(
  Offset globalPosition,
);
typedef MarkdownSelectWordCallback = void Function(DocumentPosition position);
typedef MarkdownSelectBlockCallback = void Function(int blockIndex);
typedef MarkdownSelectSelectionUnitCallback = void Function(
  Offset globalPosition,
  DocumentPosition position,
);

class MarkdownSelectionGestureDetector extends StatefulWidget {
  const MarkdownSelectionGestureDetector({
    super.key,
    required this.child,
    required this.selectionController,
    required this.selectionFocusNode,
    required this.isSelectable,
    required this.scrollableKey,
    required this.scrollController,
    required this.onRequestToolbar,
    required this.hitTestPosition,
    required this.hitTestExactTextPosition,
    required this.selectWordAt,
    required this.selectBlockAt,
    required this.selectSelectionUnitAt,
  });

  final Widget child;
  final MarkdownSelectionController selectionController;
  final FocusNode selectionFocusNode;
  final bool isSelectable;
  final GlobalKey scrollableKey;
  final ScrollController scrollController;
  final void Function(Offset) onRequestToolbar;
  final MarkdownHitTestPositionCallback hitTestPosition;
  final MarkdownHitTestExactTextPositionCallback hitTestExactTextPosition;
  final MarkdownSelectWordCallback selectWordAt;
  final MarkdownSelectBlockCallback selectBlockAt;
  final MarkdownSelectSelectionUnitCallback selectSelectionUnitAt;

  @override
  State<MarkdownSelectionGestureDetector> createState() =>
      _MarkdownSelectionGestureDetectorState();
}

class _MarkdownSelectionGestureDetectorState
    extends State<MarkdownSelectionGestureDetector> {
  static const double _autoScrollActivationZone = 56;
  static const double _autoScrollMaxSpeed = 960;
  static const Duration _autoScrollTickInterval = Duration(milliseconds: 16);

  Duration? _lastPrimaryDownTimestamp;
  Offset? _lastPrimaryDownPosition;
  int _consecutiveTapCount = 0;
  DocumentPosition? _dragBasePosition;
  Offset? _dragStartPointerPosition;
  Offset? _lastDragPointerPosition;
  bool _isDraggingSelection = false;
  bool _clearSelectionOnPointerUp = false;
  Timer? _autoScrollTimer;

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.isSelectable) {
      return;
    }
    if (!widget.selectionFocusNode.hasFocus) {
      widget.selectionFocusNode.requestFocus();
    }

    if ((event.buttons & kSecondaryMouseButton) != 0) {
      final selectionController = widget.selectionController;
      if (!selectionController.hasSelection) {
        final position = widget.hitTestPosition(event.position, clamp: true);
        if (position != null) {
          widget.selectBlockAt(position.blockIndex);
        }
      }
      widget.onRequestToolbar(event.position);
      return;
    }

    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    final exactPosition = widget.hitTestExactTextPosition(event.position);
    final position =
        exactPosition ?? widget.hitTestPosition(event.position, clamp: true);
    if (position == null) {
      widget.selectionController.clear();
      _clearSelectionOnPointerUp = false;
      return;
    }

    _updateTapCount(event);
    if (_consecutiveTapCount >= 3) {
      widget.selectSelectionUnitAt(event.position, position);
      _isDraggingSelection = false;
      _dragBasePosition = null;
      _dragStartPointerPosition = null;
      _clearSelectionOnPointerUp = false;
      return;
    }
    if (_consecutiveTapCount == 2) {
      if (exactPosition != null) {
        widget.selectWordAt(position);
      } else {
        widget.selectSelectionUnitAt(event.position, position);
      }
      _isDraggingSelection = false;
      _dragBasePosition = null;
      _dragStartPointerPosition = null;
      _clearSelectionOnPointerUp = false;
      return;
    }

    _dragBasePosition = position;
    _dragStartPointerPosition = event.position;
    _lastDragPointerPosition = event.position;
    _isDraggingSelection = true;
    _clearSelectionOnPointerUp = widget.selectionController.hasSelection;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDraggingSelection) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0 ||
        _dragBasePosition == null) {
      return;
    }
    final dragStartPointerPosition = _dragStartPointerPosition;
    if (dragStartPointerPosition != null &&
        (event.position - dragStartPointerPosition).distance < kTouchSlop) {
      _lastDragPointerPosition = event.position;
      return;
    }
    _lastDragPointerPosition = event.position;
    _updateDragSelectionAt(event.position);
    _updateAutoScroll();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDraggingSelection) {
      return;
    }
    final shouldClearSelection = _clearSelectionOnPointerUp &&
        _dragStartPointerPosition != null &&
        (event.position - _dragStartPointerPosition!).distance < kTouchSlop;
    _isDraggingSelection = false;
    _dragBasePosition = null;
    _dragStartPointerPosition = null;
    _lastDragPointerPosition = null;
    _clearSelectionOnPointerUp = false;
    _stopAutoScroll();
    if (shouldClearSelection) {
      widget.selectionController.clear();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _isDraggingSelection = false;
    _dragBasePosition = null;
    _dragStartPointerPosition = null;
    _lastDragPointerPosition = null;
    _clearSelectionOnPointerUp = false;
    _stopAutoScroll();
  }

  void _updateDragSelectionAt(Offset globalPosition) {
    if (_dragBasePosition == null) {
      return;
    }
    final position = widget.hitTestPosition(globalPosition, clamp: true);
    if (position == null) {
      return;
    }
    widget.selectionController.setSelection(
      DocumentSelection(base: _dragBasePosition!, extent: position),
    );
  }

  void _updateAutoScroll() {
    if (_autoScrollVelocity() == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
      _autoScrollTickInterval,
      (_) => _handleAutoScrollTick(),
    );
  }

  void _handleAutoScrollTick() {
    if (!_isDraggingSelection) {
      _stopAutoScroll();
      return;
    }
    if (!widget.scrollController.hasClients) {
      _stopAutoScroll();
      return;
    }
    final velocity = _autoScrollVelocity();
    if (velocity == 0) {
      _stopAutoScroll();
      return;
    }

    final position = widget.scrollController.position;
    final nextOffset = (position.pixels +
            velocity * _autoScrollTickInterval.inMilliseconds / 1000)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((nextOffset - position.pixels).abs() < 0.5) {
      _stopAutoScroll();
      return;
    }
    widget.scrollController.jumpTo(nextOffset);
    final globalPosition = _lastDragPointerPosition;
    if (globalPosition != null) {
      _updateDragSelectionAt(globalPosition);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  double _autoScrollVelocity() {
    final globalPosition = _lastDragPointerPosition;
    final viewportRect = _scrollViewportRect;
    if (globalPosition == null ||
        viewportRect == null ||
        !widget.scrollController.hasClients) {
      return 0;
    }
    final position = widget.scrollController.position;
    if (position.maxScrollExtent <= position.minScrollExtent) {
      return 0;
    }

    if (globalPosition.dy < viewportRect.top + _autoScrollActivationZone &&
        position.pixels > position.minScrollExtent) {
      final proximity = 1 -
          ((globalPosition.dy - viewportRect.top) / _autoScrollActivationZone)
              .clamp(0.0, 1.0);
      return -_autoScrollSpeedForProximity(proximity);
    }
    if (globalPosition.dy > viewportRect.bottom - _autoScrollActivationZone &&
        position.pixels < position.maxScrollExtent) {
      final proximity = ((globalPosition.dy -
                  (viewportRect.bottom - _autoScrollActivationZone)) /
              _autoScrollActivationZone)
          .clamp(0.0, 1.0);
      return _autoScrollSpeedForProximity(proximity);
    }
    return 0;
  }

  double _autoScrollSpeedForProximity(double proximity) {
    if (proximity <= 0) {
      return 0;
    }
    return math.max(80, proximity * proximity * _autoScrollMaxSpeed);
  }

  Rect? get _scrollViewportRect {
    final renderObject =
        widget.scrollableKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  void _updateTapCount(PointerDownEvent event) {
    if (_lastPrimaryDownTimestamp != null &&
        event.timeStamp - _lastPrimaryDownTimestamp! <= kDoubleTapTimeout &&
        _lastPrimaryDownPosition != null &&
        (event.position - _lastPrimaryDownPosition!).distance <=
            kDoubleTapSlop) {
      _consecutiveTapCount += 1;
    } else {
      _consecutiveTapCount = 1;
    }
    _lastPrimaryDownTimestamp = event.timeStamp;
    _lastPrimaryDownPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}

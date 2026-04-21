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

  List<_AutoScrollCandidate> _autoScrollCandidates() {
    final candidates = <_AutoScrollCandidate>[];
    final seenPositions = <ScrollPosition>{};

    final explicitCandidate = _candidateForScrollable(
      position: widget.scrollController.hasClients
          ? widget.scrollController.position
          : null,
      renderObject: widget.scrollableKey.currentContext?.findRenderObject(),
      depth: 0,
    );
    if (explicitCandidate != null) {
      seenPositions.add(explicitCandidate.position);
      candidates.add(explicitCandidate);
    }

    var depth = 1;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollableState = element.state as ScrollableState;
        final position = scrollableState.position;
        if (seenPositions.add(position)) {
          final candidate = _candidateForScrollable(
            position: position,
            renderObject: scrollableState.context.findRenderObject(),
            depth: depth,
          );
          if (candidate != null) {
            candidates.add(candidate);
          }
          depth += 1;
        }
      }
      return true;
    });
    return candidates;
  }

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
    final autoScroll = _resolveAutoScroll();
    if (autoScroll == null || autoScroll.velocity == 0) {
      _stopAutoScroll();
      return;
    }

    final position = autoScroll.candidate.position;
    if (!position.hasPixels) {
      _stopAutoScroll();
      return;
    }
    final velocity = autoScroll.velocity;
    final nextOffset = (position.pixels +
            velocity * _autoScrollTickInterval.inMilliseconds / 1000)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((nextOffset - position.pixels).abs() < 0.5) {
      _stopAutoScroll();
      return;
    }
    position.jumpTo(nextOffset);
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
    return _resolveAutoScroll()?.velocity ?? 0;
  }

  _ResolvedAutoScroll? _resolveAutoScroll() {
    final globalPosition = _lastDragPointerPosition;
    if (globalPosition == null) {
      return null;
    }

    _ResolvedAutoScroll? bestMatch;
    for (final candidate in _autoScrollCandidates()) {
      final velocity =
          _autoScrollVelocityForCandidate(candidate, globalPosition);
      if (velocity == 0) {
        continue;
      }
      if (bestMatch == null ||
          candidate.depth < bestMatch.candidate.depth ||
          (candidate.depth == bestMatch.candidate.depth &&
              candidate.viewportRect.size.longestSide <
                  bestMatch.candidate.viewportRect.size.longestSide)) {
        bestMatch =
            _ResolvedAutoScroll(candidate: candidate, velocity: velocity);
      }
    }
    return bestMatch;
  }

  double _autoScrollVelocityForCandidate(
    _AutoScrollCandidate candidate,
    Offset globalPosition,
  ) {
    final position = candidate.position;
    if (!position.hasContentDimensions ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return 0;
    }

    final viewportRect = candidate.viewportRect;
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

  _AutoScrollCandidate? _candidateForScrollable({
    required ScrollPosition? position,
    required RenderObject? renderObject,
    required int depth,
  }) {
    if (position == null) {
      return null;
    }
    if (position.axis != Axis.vertical) {
      return null;
    }
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return _AutoScrollCandidate(
      position: position,
      viewportRect: origin & renderObject.size,
      depth: depth,
    );
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

class _AutoScrollCandidate {
  const _AutoScrollCandidate({
    required this.position,
    required this.viewportRect,
    required this.depth,
  });

  final ScrollPosition position;
  final Rect viewportRect;
  final int depth;
}

class _ResolvedAutoScroll {
  const _ResolvedAutoScroll({
    required this.candidate,
    required this.velocity,
  });

  final _AutoScrollCandidate candidate;
  final double velocity;
}

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

@immutable
class MarkdownSelectionAutoScrollTarget {
  const MarkdownSelectionAutoScrollTarget({
    required this.scrollController,
    required this.viewportKey,
    required this.depth,
  });

  final ScrollController scrollController;
  final GlobalKey viewportKey;
  final int depth;
}

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
    this.additionalAutoScrollTargets,
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
  final Iterable<MarkdownSelectionAutoScrollTarget> Function()?
      additionalAutoScrollTargets;

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
    if (!mounted) {
      return const <_AutoScrollCandidate>[];
    }
    final candidates = <_AutoScrollCandidate>[];
    final seenPositions = <ScrollPosition>{};

    for (final target in widget.additionalAutoScrollTargets?.call() ??
        const <MarkdownSelectionAutoScrollTarget>[]) {
      final candidate = _candidateForScrollable(
        position: target.scrollController.hasClients
            ? target.scrollController.position
            : null,
        renderObject: target.viewportKey.currentContext?.findRenderObject(),
        depth: target.depth,
      );
      if (candidate != null && seenPositions.add(candidate.position)) {
        candidates.add(candidate);
      }
    }

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
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
    _isDraggingSelection = false;
    _dragBasePosition = null;
    _dragStartPointerPosition = null;
    _lastDragPointerPosition = null;
    _clearSelectionOnPointerUp = false;
    _stopAutoScroll();
  }

  void _updateDragSelectionAt(Offset globalPosition) {
    if (!mounted || _dragBasePosition == null) {
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
    if (!mounted) {
      _stopAutoScroll();
      return;
    }
    if (_resolveAutoScrolls().isEmpty) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
      _autoScrollTickInterval,
      (_) => _handleAutoScrollTick(),
    );
  }

  void _handleAutoScrollTick() {
    if (!mounted || !_isDraggingSelection) {
      _stopAutoScroll();
      return;
    }
    final autoScrolls = _resolveAutoScrolls();
    if (autoScrolls.isEmpty) {
      _stopAutoScroll();
      return;
    }

    var scrolled = false;
    for (final autoScroll in autoScrolls) {
      final position = autoScroll.candidate.position;
      if (!position.hasPixels) {
        continue;
      }
      final velocity = autoScroll.velocity;
      final nextOffset = (position.pixels +
              velocity * _autoScrollTickInterval.inMilliseconds / 1000)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((nextOffset - position.pixels).abs() < 0.5) {
        continue;
      }
      position.jumpTo(nextOffset);
      scrolled = true;
    }
    if (!scrolled) {
      _stopAutoScroll();
      return;
    }
    final globalPosition = _lastDragPointerPosition;
    if (globalPosition != null) {
      _updateDragSelectionAt(globalPosition);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  List<_ResolvedAutoScroll> _resolveAutoScrolls() {
    if (!mounted) {
      return const <_ResolvedAutoScroll>[];
    }
    final globalPosition = _lastDragPointerPosition;
    if (globalPosition == null) {
      return const <_ResolvedAutoScroll>[];
    }

    final bestMatches = <Axis, _ResolvedAutoScroll>{};
    for (final candidate in _autoScrollCandidates()) {
      final velocity =
          _autoScrollVelocityForCandidate(candidate, globalPosition);
      if (velocity == 0) {
        continue;
      }
      final resolved =
          _ResolvedAutoScroll(candidate: candidate, velocity: velocity);
      final existing = bestMatches[candidate.axis];
      if (existing == null ||
          _isPreferredAutoScrollCandidate(resolved, existing)) {
        bestMatches[candidate.axis] = resolved;
      }
    }
    return bestMatches.values.toList(growable: false);
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
    if (_shouldSuppressAncestorAutoScroll(candidate, globalPosition)) {
      return 0;
    }

    final viewportRect = candidate.viewportRect;
    if (!_isWithinCandidateCrossAxisBand(candidate, globalPosition)) {
      return 0;
    }

    switch (candidate.axis) {
      case Axis.vertical:
        if (globalPosition.dy < viewportRect.top + _autoScrollActivationZone &&
            position.pixels > position.minScrollExtent) {
          final proximity = 1 -
              ((globalPosition.dy - viewportRect.top) /
                      _autoScrollActivationZone)
                  .clamp(0.0, 1.0);
          return -_autoScrollSpeedForProximity(proximity);
        }
        if (globalPosition.dy >
                viewportRect.bottom - _autoScrollActivationZone &&
            position.pixels < position.maxScrollExtent) {
          final proximity = ((globalPosition.dy -
                      (viewportRect.bottom - _autoScrollActivationZone)) /
                  _autoScrollActivationZone)
              .clamp(0.0, 1.0);
          return _autoScrollSpeedForProximity(proximity);
        }
      case Axis.horizontal:
        if (globalPosition.dx < viewportRect.left + _autoScrollActivationZone &&
            position.pixels > position.minScrollExtent) {
          final proximity = 1 -
              ((globalPosition.dx - viewportRect.left) /
                      _autoScrollActivationZone)
                  .clamp(0.0, 1.0);
          return -_autoScrollSpeedForProximity(proximity);
        }
        if (globalPosition.dx >
                viewportRect.right - _autoScrollActivationZone &&
            position.pixels < position.maxScrollExtent) {
          final proximity = ((globalPosition.dx -
                      (viewportRect.right - _autoScrollActivationZone)) /
                  _autoScrollActivationZone)
              .clamp(0.0, 1.0);
          return _autoScrollSpeedForProximity(proximity);
        }
    }
    return 0;
  }

  bool _isWithinCandidateCrossAxisBand(
    _AutoScrollCandidate candidate,
    Offset globalPosition,
  ) {
    final viewportRect = candidate.viewportRect;
    switch (candidate.axis) {
      case Axis.vertical:
        return globalPosition.dx >=
                viewportRect.left - _autoScrollActivationZone &&
            globalPosition.dx <= viewportRect.right + _autoScrollActivationZone;
      case Axis.horizontal:
        return globalPosition.dy >=
                viewportRect.top - _autoScrollActivationZone &&
            globalPosition.dy <=
                viewportRect.bottom + _autoScrollActivationZone;
    }
  }

  double _autoScrollSpeedForProximity(double proximity) {
    if (proximity <= 0) {
      return 0;
    }
    return math.max(80, proximity * proximity * _autoScrollMaxSpeed);
  }

  bool _shouldSuppressAncestorAutoScroll(
    _AutoScrollCandidate candidate,
    Offset globalPosition,
  ) {
    if (candidate.depth == 0) {
      return false;
    }
    final markdownRect = _markdownContentRect;
    if (markdownRect == null) {
      return false;
    }
    final viewportRect = candidate.viewportRect;
    const epsilon = 0.5;
    switch (candidate.axis) {
      case Axis.vertical:
        final isNearTop =
            globalPosition.dy < viewportRect.top + _autoScrollActivationZone;
        final isNearBottom =
            globalPosition.dy > viewportRect.bottom - _autoScrollActivationZone;
        if (isNearBottom) {
          return markdownRect.bottom <= viewportRect.bottom + epsilon;
        }
        if (isNearTop) {
          return markdownRect.top >= viewportRect.top - epsilon;
        }
      case Axis.horizontal:
        final isNearLeft =
            globalPosition.dx < viewportRect.left + _autoScrollActivationZone;
        final isNearRight =
            globalPosition.dx > viewportRect.right - _autoScrollActivationZone;
        if (isNearRight) {
          return markdownRect.right <= viewportRect.right + epsilon;
        }
        if (isNearLeft) {
          return markdownRect.left >= viewportRect.left - epsilon;
        }
    }
    return false;
  }

  _AutoScrollCandidate? _candidateForScrollable({
    required ScrollPosition? position,
    required RenderObject? renderObject,
    required int depth,
  }) {
    if (position == null) {
      return null;
    }
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return _AutoScrollCandidate(
      position: position,
      axis: position.axis,
      viewportRect: origin & renderObject.size,
      depth: depth,
    );
  }

  bool _isPreferredAutoScrollCandidate(
    _ResolvedAutoScroll candidate,
    _ResolvedAutoScroll existing,
  ) {
    if (candidate.candidate.depth != existing.candidate.depth) {
      return candidate.candidate.depth < existing.candidate.depth;
    }
    return candidate.candidate.viewportRect.size.longestSide <
        existing.candidate.viewportRect.size.longestSide;
  }

  Rect? get _markdownContentRect {
    if (!mounted) {
      return null;
    }
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

class _AutoScrollCandidate {
  const _AutoScrollCandidate({
    required this.position,
    required this.axis,
    required this.viewportRect,
    required this.depth,
  });

  final ScrollPosition position;
  final Axis axis;
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

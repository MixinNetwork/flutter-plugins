import 'dart:async';

import 'package:flutter/widgets.dart';

import 'drop_coordinator.dart';
import 'drop_item.dart';
import 'drop_offer.dart';

@immutable
class DropEventDetails {
  const DropEventDetails({
    required this.offer,
    required this.localPosition,
    required this.globalPosition,
    this.operation = DropOperation.reject,
  });

  final DropOffer offer;
  final Offset localPosition;
  final Offset globalPosition;
  Set<DropOperation> get allowedOperations => offer.allowedOperations;

  /// Reject while deciding; the selected operation in hover and drop callbacks.
  final DropOperation operation;
}

/// An accepted drop. Provider references are valid only during [DropTarget.onDrop].
@immutable
class DropEvent extends DropEventDetails {
  DropEvent({
    required super.offer,
    required super.localPosition,
    required super.globalPosition,
    required List<DropItem> items,
    required super.operation,
  }) : items = List.unmodifiable(items);

  final List<DropItem> items;
}

typedef OnDropCallback = FutureOr<void> Function(DropEvent event);
typedef OnDragCallback<T> = void Function(T details);
typedef DropDecisionCallback = DropOperation Function(DropEventDetails details);

/// An OS drop destination selected using Flutter's actual hit-test path.
///
/// The first enabled target whose [onDropDecision] returns an allowed operation
/// receives the event. A rejecting child can fall back to an accepting ancestor. Opaque
/// widgets still occlude siblings behind them, just as for Flutter pointer
/// events.
class DropTarget extends StatefulWidget {
  const DropTarget({
    super.key,
    required this.child,
    required this.onDropDecision,
    this.onDragEntered,
    this.onDragExited,
    this.onDrop,
    this.onDragUpdated,
    this.enable = true,
    this.behavior = HitTestBehavior.translucent,
  });

  final Widget child;

  /// A short, synchronous decision using the offer and current application
  /// state. Do not change widget state, perform I/O, or wait on platform calls
  /// here. Reject, unsupported operations, and exceptions allow the next target
  /// in the hit-test path to decide. The operation is reported to the source;
  /// the final native acceptance can precede asynchronous processing.
  final DropDecisionCallback onDropDecision;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragCallback<DropEventDetails>? onDragUpdated;

  /// Reads that depend on the drag source must be awaited in this callback.
  /// Adapters automatically release event resources when it completes, including
  /// on failure. Save any needed content before returning. Native completion is
  /// deferred where the source protocol supports it. Throw to report failure.
  final OnDropCallback? onDrop;
  final bool enable;
  final HitTestBehavior behavior;

  @override
  State<DropTarget> createState() => _DropTargetState();
}

class _DropTargetState extends State<DropTarget> implements DropTargetClient {
  @override
  final int id = DropCoordinator.nextTargetId();
  int? _view;

  @override
  int get view => _view!;
  @override
  bool get enabled => mounted && widget.enable;
  @override
  RenderBox? get box => context.findRenderObject() as RenderBox?;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewId = View.of(context).viewId;
    if (_view == viewId) return;
    if (_view != null) DropCoordinator.instance.remove(this);
    _view = viewId;
    DropCoordinator.instance.add(this);
  }

  @override
  void didUpdateWidget(DropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enable && oldWidget.enable) {
      DropCoordinator.instance.disabled(this);
    }
  }

  @override
  DropOperation decide(DropEventDetails details) =>
      widget.onDropDecision(details);
  @override
  void entered(DropEventDetails details) => widget.onDragEntered?.call(details);
  @override
  void updated(DropEventDetails details) => widget.onDragUpdated?.call(details);
  @override
  void exited(DropEventDetails details) => widget.onDragExited?.call(details);
  @override
  FutureOr<void> dropped(DropEvent details) => widget.onDrop?.call(details);

  @override
  void dispose() {
    DropCoordinator.instance.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: this, behavior: widget.behavior, child: widget.child);
}

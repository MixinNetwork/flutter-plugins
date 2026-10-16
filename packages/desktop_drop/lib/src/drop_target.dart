import 'dart:async';

import 'package:flutter/widgets.dart';

import 'drop_coordinator.dart';
import 'drop_item.dart';
import 'drop_offer.dart';

/// Metadata available while deciding or hovering. Preview fields may be absent.
@immutable
class DragDetails {
  DragDetails({
    required List<DropItemPreview> items,
    required this.localPosition,
    required this.globalPosition,
  }) : items = List.unmodifiable(items);

  final List<DropItemPreview> items;
  final Offset localPosition;
  final Offset globalPosition;
}

/// Received content. Await provider reads inside [DropTarget.onDrop].
@immutable
class DropDetails {
  DropDetails({
    required List<DropItem> items,
    required this.localPosition,
    required this.globalPosition,
    required this.operation,
  }) : items = List.unmodifiable(items);

  final List<DropItem> items;
  final Offset localPosition;
  final Offset globalPosition;
  final DropOperation operation;
}

typedef OnDropCallback = FutureOr<void> Function(DropDetails details);
typedef OnDragCallback = void Function(DragDetails details);
typedef DropAcceptanceCallback = bool Function(DragDetails details);

/// An OS drop destination selected using Flutter's actual hit-test path.
///
/// The first enabled target accepting the kinds, operation, and optional
/// [onWillAccept] condition receives the event. A rejecting child can fall back
/// to an accepting ancestor. Opaque widgets occlude siblings behind them.
class DropTarget extends StatefulWidget {
  const DropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    this.acceptedKinds = const {
      DropItemKind.file,
      DropItemKind.string,
      DropItemKind.directory,
    },
    this.onWillAccept,
    this.operation = DropOperation.copy,
    this.onEnter,
    this.onMove,
    this.onLeave,
    this.enabled = true,
    this.behavior = HitTestBehavior.translucent,
  });

  final Widget child;

  /// Accept when at least one preview matches. Does not filter delivered items.
  /// An empty set rejects all drags. Incomplete file previews are tentatively
  /// allowed for directory targets until the source reveals their kind.
  final Set<DropItemKind> acceptedKinds;

  /// An optional synchronous condition, checked after kinds and operation.
  /// Keep it fast: do not change widget state, perform I/O, or make platform
  /// calls. Missing preview fields do not necessarily mean missing content.
  /// False or an exception lets the next target in the hit-test path decide.
  final DropAcceptanceCallback? onWillAccept;

  /// The operation reported to the source. Unsupported operations reject;
  /// they are never substituted. Move can cause the source to remove its data.
  /// Native acceptance can precede asynchronous application processing.
  final DropOperation operation;

  final OnDragCallback? onEnter;
  final OnDragCallback? onMove;

  /// Clears an accepted hover when leaving, rejecting, dropping, or disabling.
  /// Not called after this target is disposed.
  final VoidCallback? onLeave;

  /// Await source reads and directory listings before returning. Resources are
  /// released automatically on completion or failure. Save content here if it
  /// is needed later. Completion cannot universally undo a native operation.
  final OnDropCallback onDrop;
  final bool enabled;
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
  bool get enabled => mounted && widget.enabled;
  @override
  DropOperation get operation => widget.operation;
  @override
  Set<DropItemKind> get acceptedKinds => widget.acceptedKinds;
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
    if (!widget.enabled && oldWidget.enabled) {
      DropCoordinator.instance.disabled(this);
    }
  }

  @override
  bool accepts(DragDetails details) =>
      widget.onWillAccept?.call(details) ?? true;
  @override
  void entered(DragDetails details) => widget.onEnter?.call(details);
  @override
  void updated(DragDetails details) => widget.onMove?.call(details);
  @override
  void exited() => widget.onLeave?.call();
  @override
  FutureOr<void> dropped(DropDetails details) => widget.onDrop(details);

  @override
  void dispose() {
    DropCoordinator.instance.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: this, behavior: widget.behavior, child: widget.child);
}

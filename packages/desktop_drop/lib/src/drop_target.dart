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
  });

  final DropOffer offer;
  final Offset localPosition;
  final Offset globalPosition;
}

@immutable
class DropDoneDetails extends DropEventDetails {
  DropDoneDetails({
    required super.offer,
    required super.localPosition,
    required super.globalPosition,
    required List<DropItem> files,
    this.rawText,
  }) : files = List.unmodifiable(files);

  final List<DropItem> files;
  String? get text => offer.text;
  List<Uri> get urls => offer.urls;

  /// Original Linux URI-list or portal transfer key. Portal keys have already
  /// been resolved by native code and must not be retrieved a second time.
  final String? rawText;
}

typedef OnDragDoneCallback = void Function(DropDoneDetails details);
typedef OnDragCallback<T> = void Function(T details);
typedef DropAcceptPredicate = bool Function(DropEventDetails details);

/// An OS drop destination selected using Flutter's actual hit-test path.
///
/// The first enabled target whose [onWillAccept] returns true receives the
/// event. A rejecting child can fall back to an accepting ancestor. Opaque
/// widgets still occlude siblings behind them, just as for Flutter pointer
/// events.
class DropTarget extends StatefulWidget {
  const DropTarget({
    super.key,
    required this.child,
    required this.onWillAccept,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
    this.enable = true,
    this.behavior = HitTestBehavior.translucent,
  });

  final Widget child;

  /// A short, synchronous decision using the offer and current application
  /// state. Do not change widget state, perform I/O, or wait on platform calls
  /// here. Exceptions reject this candidate. Returning false allows the next
  /// target in the hit-test path to decide.
  final DropAcceptPredicate onWillAccept;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragCallback<DropEventDetails>? onDragUpdated;
  final OnDragDoneCallback? onDragDone;
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
  bool accepts(DropEventDetails details) => widget.onWillAccept(details);
  @override
  void entered(DropEventDetails details) => widget.onDragEntered?.call(details);
  @override
  void updated(DropEventDetails details) => widget.onDragUpdated?.call(details);
  @override
  void exited(DropEventDetails details) => widget.onDragExited?.call(details);
  @override
  void dropped(DropDoneDetails details) => widget.onDragDone?.call(details);

  @override
  void dispose() {
    DropCoordinator.instance.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: this, behavior: widget.behavior, child: widget.child);
}

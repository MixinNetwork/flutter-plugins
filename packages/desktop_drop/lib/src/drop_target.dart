import 'package:flutter/widgets.dart';

import 'channel.dart';
import 'events.dart';

typedef OnDragDoneCallback = void Function(List<Uri> urls);

class DropTarget extends StatefulWidget {
  const DropTarget({
    Key? key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
    this.enable = true,
  }) : super(key: key);

  final Widget child;

  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  final VoidCallback? onDragUpdated;

  final OnDragDoneCallback? onDragDone;

  final bool enable;

  @override
  State<DropTarget> createState() => _DropTargetState();
}

enum _DragTargetStatus {
  enter,
  update,
  idle,
}

class _DropTargetState extends State<DropTarget> {
  _DragTargetStatus _status = _DragTargetStatus.idle;

  @override
  void initState() {
    super.initState();
    DesktopDrop.instance.init();
    if (widget.enable) {
      DesktopDrop.instance.addRawDropEventListener(_onDropEvent);
    }
  }

  void didUpdateWidget(DropTarget oldWidget) {
    if (widget.enable && !oldWidget.enable) {
      DesktopDrop.instance.addRawDropEventListener(_onDropEvent);
    } else if (!widget.enable && oldWidget.enable) {
      DesktopDrop.instance.removeRawDropEventListener(_onDropEvent);
      if (_status != _DragTargetStatus.idle) {
        _updateStatus(_DragTargetStatus.idle);
      }
    }
  }

  void _onDropEvent(DropEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final position = renderBox.globalToLocal(event.location);
    bool inBounds = renderBox.paintBounds.contains(position);
    if (event is DropEnterEvent) {
      if (!inBounds) {
        assert(_status == _DragTargetStatus.idle);
      } else {
        _updateStatus(_DragTargetStatus.enter);
      }
    } else if (event is DropUpdateEvent) {
      if (_status == _DragTargetStatus.idle && inBounds) {
        _updateStatus(_DragTargetStatus.enter);
      } else if (_status == _DragTargetStatus.enter && inBounds) {
        _updateStatus(_DragTargetStatus.update);
      } else if (_status != _DragTargetStatus.idle && !inBounds) {
        _updateStatus(_DragTargetStatus.idle);
      }
    } else if (event is DropExitEvent && _status != _DragTargetStatus.idle) {
      _updateStatus(_DragTargetStatus.idle);
    } else if (event is DropDoneEvent &&
        _status != _DragTargetStatus.idle &&
        inBounds) {
      _updateStatus(_DragTargetStatus.idle);
      widget.onDragDone?.call(event.uris);
    }
  }

  void _updateStatus(_DragTargetStatus status) {
    assert(_status != status);
    _status = status;
    switch (_status) {
      case _DragTargetStatus.enter:
        widget.onDragEntered?.call();
        break;
      case _DragTargetStatus.update:
        widget.onDragUpdated?.call();
        break;
      case _DragTargetStatus.idle:
        widget.onDragExited?.call();
        break;
    }
  }

  @override
  void dispose() {
    if (widget.enable) {
      DesktopDrop.instance.removeRawDropEventListener(_onDropEvent);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

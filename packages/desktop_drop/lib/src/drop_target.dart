import 'package:flutter/widgets.dart';
import 'package:universal_platform/universal_platform.dart';

import 'channel.dart';
import 'drop_item.dart';
import 'events.dart';

@immutable
class DropDoneDetails {
  const DropDoneDetails({
    required this.files,
    required this.localPosition,
    required this.globalPosition,
  });

  final List<DropItem> files;
  final Offset localPosition;
  final Offset globalPosition;
}

class DropEventDetails {
  DropEventDetails({
    required this.localPosition,
    required this.globalPosition,
  });

  final Offset localPosition;

  final Offset globalPosition;
}

typedef OnDragDoneCallback = void Function(DropDoneDetails details);

typedef OnDragCallback<Detail> = void Function(Detail details);

/// A widget that accepts draggable files.
class DropTarget extends StatefulWidget {
  const DropTarget({
    super.key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
    this.enable = true,
  });

  final Widget child;

  /// Callback when drag entered target area.
  final OnDragCallback<DropEventDetails>? onDragEntered;

  /// Callback when drag exited target area.
  final OnDragCallback<DropEventDetails>? onDragExited;

  /// Callback when drag hover on target area.
  final OnDragCallback<DropEventDetails>? onDragUpdated;

  /// Callback when drag dropped on target area.
  final OnDragDoneCallback? onDragDone;

  /// Whether to enable drop target.
  ///
  /// ATTENTION: You should disable drop target when you push a new page/widget in
  /// front of this drop target, since the drop target will still receive drag events
  /// even it is invisible.
  /// https://github.com/MixinNetwork/flutter-plugins/issues/2
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

  @override
  void didUpdateWidget(DropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enable && !oldWidget.enable) {
      DesktopDrop.instance.addRawDropEventListener(_onDropEvent);
    } else if (!widget.enable && oldWidget.enable) {
      DesktopDrop.instance.removeRawDropEventListener(_onDropEvent);
      if (_status != _DragTargetStatus.idle) {
        _updateStatus(
          _DragTargetStatus.idle,
          localLocation: Offset.zero,
          globalLocation: Offset.zero,
        );
      }
    }
  }

  void _onDropEvent(DropEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final globalPosition = _scaleHoverPoint(context, event.location);
    final position = renderBox.globalToLocal(globalPosition);
    bool inBounds = renderBox.paintBounds.contains(position);
    if (event is DropEnterEvent) {
      if (!inBounds) {
        assert(_status == _DragTargetStatus.idle);
      } else {
        _updateStatus(
          _DragTargetStatus.enter,
          globalLocation: globalPosition,
          localLocation: position,
        );
      }
    } else if (event is DropUpdateEvent) {
      if (_status == _DragTargetStatus.idle && inBounds) {
        _updateStatus(
          _DragTargetStatus.enter,
          globalLocation: globalPosition,
          localLocation: position,
        );
      } else if ((_status == _DragTargetStatus.enter ||
              _status == _DragTargetStatus.update) &&
          inBounds) {
        _updateStatus(
          _DragTargetStatus.update,
          globalLocation: globalPosition,
          localLocation: position,
          debugRequiredStatus: false,
        );
      } else if (_status != _DragTargetStatus.idle && !inBounds) {
        _updateStatus(
          _DragTargetStatus.idle,
          globalLocation: globalPosition,
          localLocation: position,
        );
      }
    } else if (event is DropExitEvent && _status != _DragTargetStatus.idle) {
      _updateStatus(
        _DragTargetStatus.idle,
        globalLocation: globalPosition,
        localLocation: position,
      );
    } else if (event is DropDoneEvent &&
        (_status != _DragTargetStatus.idle || UniversalPlatform.isLinux) &&
        inBounds) {
      _updateStatus(
        _DragTargetStatus.idle,
        debugRequiredStatus: false,
        globalLocation: globalPosition,
        localLocation: position,
      );
      widget.onDragDone?.call(DropDoneDetails(
        files: event.files,
        localPosition: position,
        globalPosition: globalPosition,
      ));
    }
  }

  void _updateStatus(
    _DragTargetStatus status, {
    bool debugRequiredStatus = true,
    required Offset localLocation,
    required Offset globalLocation,
  }) {
    assert(!debugRequiredStatus || _status != status);
    _status = status;
    final details = DropEventDetails(
      localPosition: localLocation,
      globalPosition: globalLocation,
    );
    switch (_status) {
      case _DragTargetStatus.enter:
        widget.onDragEntered?.call(details);
        break;
      case _DragTargetStatus.update:
        widget.onDragUpdated?.call(details);
        break;
      case _DragTargetStatus.idle:
        widget.onDragExited?.call(details);
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

Offset _scaleHoverPoint(BuildContext context, Offset point) {
  if (UniversalPlatform.isWindows || UniversalPlatform.isAndroid) {
    return point.scale(
      1 / MediaQuery.of(context).devicePixelRatio,
      1 / MediaQuery.of(context).devicePixelRatio,
    );
  }
  return point;
}

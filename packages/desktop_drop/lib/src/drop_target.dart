import 'package:cross_file/cross_file.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'channel.dart';
import 'events.dart';
import 'utils/platform.dart' if (dart.library.html) 'utils/platform_web.dart';

@immutable
class DropDoneDetails {
  const DropDoneDetails({
    required this.files,
    required this.localPosition,
    required this.globalPosition,
  });

  final List<XFile> files;
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
    Key? key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
    this.enable = true,
  }) : super(key: key);

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

class _DropTargetState extends State<DropTarget> implements RawDropListener {
  _DragTargetStatus _status = _DragTargetStatus.idle;
  Offset? _latestGlobalPosition;
  Offset? _latestLocalPosition;

  @override
  void initState() {
    super.initState();
    DesktopDrop.instance.init();
    if (widget.enable) {
      DesktopDrop.instance.addRawDropEventListener(this);
    }
  }

  @override
  void didUpdateWidget(DropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enable != oldWidget.enable) {
      if (!widget.enable) {
        _updateStatus(
          _DragTargetStatus.idle,
          localLocation: Offset.zero,
          globalLocation: Offset.zero,
        );
      }
    }
  }

  void _updateStatus(
    _DragTargetStatus status, {
    bool debugRequiredStatus = true,
    required Offset localLocation,
    required Offset globalLocation,
  }) {
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
        _latestGlobalPosition = null;
        _latestLocalPosition = null;
        widget.onDragExited?.call(details);
        break;
    }
  }

  @override
  void dispose() {
    if (widget.enable) {
      DesktopDrop.instance.removeRawDropEventListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  bool isInBounds(DropEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !widget.enable) {
      return false;
    }
    final globalPosition = _scaleHoverPoint(event.location);
    final position = renderBox.globalToLocal(globalPosition);
    _latestGlobalPosition = globalPosition;
    _latestLocalPosition = position;

    return renderBox.hitTest(BoxHitTestResult(), position: position);
  }

  @override
  void onEvent(DropEvent event) {
    final inBounds = isInBounds(event);
    final position = _latestLocalPosition;
    final globalPosition = _latestGlobalPosition;
    if (position == null || globalPosition == null) {
      return;
    }
    if (event is DropEnterEvent) {
      if (!inBounds) {
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
      } else if ((_status == _DragTargetStatus.enter || _status == _DragTargetStatus.update) && inBounds) {
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
    } else if (event is DropDoneEvent && (_status != _DragTargetStatus.idle || Platform.isLinux) && inBounds) {
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

  Offset _scaleHoverPoint(Offset point) {
    if (Platform.isWindows || Platform.isAndroid) {
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final scaleAmount = 1 / pixelRatio;
      return point.scale(scaleAmount, scaleAmount);
    }
    return point;
  }
}

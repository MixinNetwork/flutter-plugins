import 'package:cross_file/cross_file.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'channel.dart';
import 'events.dart';

typedef OnDragDoneCallback = void Function(List<XFile> files, Offset localPosition);

typedef OnDragCallback = void Function(Offset localPosition);

typedef OnDragActiveStatusChange = void Function(bool isActive);

/// A widget that accepts draggable files.
class DropTarget extends SingleChildRenderObjectWidget {
  const DropTarget({
    Key? key,
    super.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
    this.onDragActiveStatusChange,
    this.isEnabled = true,
  }) : super(key: key);

  /// Callback when drag entered target area.
  final OnDragCallback? onDragEntered;

  /// Callback when drag exited target area.
  final OnDragCallback? onDragExited;

  /// Callback when drag hover on target area.
  final OnDragCallback? onDragUpdated;

  /// Callback when drag dropped on target area.
  final OnDragDoneCallback? onDragDone;

  final OnDragActiveStatusChange? onDragActiveStatusChange;

  final bool isEnabled;

  @override
  _DropTargetRenderObject createRenderObject(BuildContext context) => _DropTargetRenderObject(
        isEnabled: isEnabled,
        onDragEntered: onDragEntered,
        onDragExited: onDragExited,
        onDragUpdated: onDragUpdated,
        onDragDone: onDragDone,
        onDragActiveStatusChange: onDragActiveStatusChange,
      );

  @override
  void updateRenderObject(BuildContext context, covariant _DropTargetRenderObject renderObject) {
    renderObject
      ..isEnabled = isEnabled
      ..onDragEntered = onDragEntered
      ..onDragExited = onDragExited
      ..onDragUpdated = onDragUpdated
      ..onDragDone = onDragDone
      ..onDragActiveStatusChange = onDragActiveStatusChange;
  }
}

class _DropTargetRenderObject extends RenderProxyBoxWithHitTestBehavior implements RawDropListener {
  _DropTargetRenderObject({
    required bool isEnabled,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragUpdated,
    required this.onDragDone,
    required this.onDragActiveStatusChange,
  }) : super(behavior: HitTestBehavior.opaque) {
    DesktopDrop.instance.init();
    this.isEnabled = isEnabled;
  }

  bool _isActive = false;
  set isActive(bool newValue) {
    if (newValue == _isActive) {
      return;
    }
    final position = _latestLocalPosition!;
    if (newValue) {
      if (_isActive) {
        onDragUpdated?.call(position);
      } else {
        onDragEntered?.call(position);
      }
    } else {
      _latestLocalPosition = null;
      onDragExited?.call(position);
    }
    _isActive = newValue;
    onDragActiveStatusChange?.call(newValue);
  }

  bool _isEnabled = false;
  set isEnabled(bool value) {
    if (value != _isEnabled) {
      _isEnabled = value;
      if (!value) {
        isActive = false;
      }
    }
  }

  /// Callback when drag entered target area.
  OnDragCallback? onDragEntered;

  /// Callback when drag exited target area.
  OnDragCallback? onDragExited;

  /// Callback when drag hover on target area.
  OnDragCallback? onDragUpdated;

  /// Callback when drag dropped on target area.
  OnDragDoneCallback? onDragDone;

  OnDragActiveStatusChange? onDragActiveStatusChange;

  Offset? _latestLocalPosition;

  @override
  void dispose() {
    isEnabled = false;
    super.dispose();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_isEnabled) {
      return child?.hitTest(result, position: position) ?? false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool handleDropEvent(DropEvent event) {
    _latestLocalPosition = event.location;

    if (!_isEnabled) {
      isActive = false;
      return false;
    }

    if (event is DropEnterEvent || event is DropUpdateEvent) {
      isActive = true;
    } else if (event is DropExitEvent) {
      isActive = false;
    } else if (event is DropDoneEvent) {
      onDragDone?.call(event.files, _latestLocalPosition!);
      isActive = false;
    }
    return true;
  }

  @override
  Offset globalToLocalOffset(Offset global) => globalToLocal(global);
}

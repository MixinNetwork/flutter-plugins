// You have generated a new plugin project without
// specifying the `--platforms` flag. A plugin project supports no platforms is generated.
// To add platforms, run `flutter create -t plugin --platforms <platforms> .` under the same
// directory. You can also find a detailed instruction on how to add platforms in the `pubspec.yaml` at https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract class DropEvent {
  Offset location;

  DropEvent(this.location);

  @override
  String toString() {
    return '$runtimeType($location)';
  }
}

class DropEnterEvent extends DropEvent {
  DropEnterEvent({required Offset location}) : super(location);
}

class DropExitEvent extends DropEvent {
  DropExitEvent({required Offset location}) : super(location);
}

class DropUpdateEvent extends DropEvent {
  DropUpdateEvent({required Offset location}) : super(location);
}

class DropDoneEvent extends DropEvent {
  final List<Uri> uris;

  DropDoneEvent({
    required Offset location,
    required this.uris,
  }) : super(location);

  @override
  String toString() {
    return '$runtimeType($location, $uris)';
  }
}

typedef RawDropListener = void Function(DropEvent);

class DesktopDrop {
  static const MethodChannel _channel = MethodChannel('desktop_drop');

  static final _instance = DesktopDrop();

  final _listeners = <RawDropListener>{};

  var _inited = false;

  Offset? _offset;

  void init() {
    if (_inited) {
      return;
    }
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      try {
        return await _handleMethodChannel(call);
      } catch (e, s) {
        debugPrint('_handleMethodChannel: $e $s');
      }
    });
  }

  Future<void> _handleMethodChannel(MethodCall call) async {
    switch (call.method) {
      case "entered":
        assert(_offset == null);
        final position = (call.arguments as List).cast<double>();
        _offset = Offset(position[0], position[1]);
        _notifyEvent(DropEnterEvent(location: _offset!));
        break;
      case "updated":
        assert(_offset != null);
        final position = (call.arguments as List).cast<double>();
        _offset = Offset(position[0], position[1]);
        _notifyEvent(DropUpdateEvent(location: _offset!));
        break;
      case "exited":
        assert(_offset != null);
        _notifyEvent(DropExitEvent(location: _offset ?? Offset.zero));
        _offset = null;
        break;
      case "performOpeartion":
        assert(_offset != null);
        final urls = (call.arguments as List).cast<String>();
        _notifyEvent(
          DropDoneEvent(
              location: _offset ?? Offset.zero,
              uris: urls
                  .map((e) => Uri.tryParse(e))
                  .where((e) => e != null)
                  .cast<Uri>()
                  .toList()),
        );
        _offset = null;
        break;
      default:
        throw UnimplementedError('${call.method} not implement.');
    }
  }

  void _notifyEvent(DropEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }

  void addRawDropEventListener(RawDropListener listener) {
    assert(!_listeners.contains(listener));
    _listeners.add(listener);
  }

  void removeRawDropEventListener(RawDropListener listener) {
    assert(_listeners.contains(listener));
    _listeners.remove(listener);
  }
}

typedef OnDragDoneCallback = void Function(List<Uri> urls);

class DropTarget extends StatefulWidget {
  const DropTarget({
    Key? key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onDragUpdated,
  }) : super(key: key);

  final Widget child;

  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  final VoidCallback? onDragUpdated;

  final OnDragDoneCallback? onDragDone;

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
    DesktopDrop._instance.init();
    DesktopDrop._instance.addRawDropEventListener(_onDropEvent);
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
    DesktopDrop._instance.removeRawDropEventListener(_onDropEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

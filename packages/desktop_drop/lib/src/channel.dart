import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'events.dart';
import 'utils/platform.dart' if (dart.library.html) 'utils/platform_web.dart';

typedef RawDropListener = void Function(DropEvent);

class DesktopDrop {
  static const MethodChannel _channel = MethodChannel('desktop_drop');

  DesktopDrop._();

  static final instance = DesktopDrop._();

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
        if (_offset == null && Platform.isLinux) {
          final position = (call.arguments as List).cast<double>();
          _offset = Offset(position[0], position[1]);
          _notifyEvent(DropEnterEvent(location: _offset!));
          return;
        }
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
      case "performOperation":
        assert(_offset != null);
        final urls = (call.arguments as List).cast<String>();
        _notifyEvent(
          DropDoneEvent(
              location: _offset ?? Offset.zero,
              uris: urls
                  .map(
                      (e) => Platform.isWindows ? Uri.file(e) : Uri.tryParse(e))
                  .where((e) => e != null)
                  .cast<Uri>()
                  .toList()),
        );
        _offset = null;
        break;
      case "performOperation_linux":
        // gtk notify 'exit' before 'performOperation'.
        assert(_offset == null);
        final text = (call.arguments as List<dynamic>)[0] as String;
        final offset = ((call.arguments as List<dynamic>)[1] as List<dynamic>)
            .cast<double>();
        final lines = const LineSplitter().convert(text);
        _notifyEvent(DropDoneEvent(
          location: Offset(offset[0], offset[1]),
          uris: lines
              .map((e) => Uri.tryParse(e))
              .where((e) => e != null)
              .cast<Uri>()
              .toList(),
        ));
        break;
      case "performOperation_web":
        debugPrint('call.arguments: ${call.arguments}');
        assert(_offset != null);
        _notifyEvent(
          DropDoneEvent(location: _offset ?? Offset.zero, uris: []),
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

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'drop_item.dart';
import 'events.dart';
import 'utils/platform.dart' if (dart.library.html) 'utils/platform_web.dart';

abstract class RawDropListener {
  void onEvent(DropEvent event);
  bool isInBounds(DropEvent event);
}

class DesktopDrop {
  static const MethodChannel _channel = MethodChannel('desktop_drop');

  DesktopDrop._();

  static final instance = DesktopDrop._();

  final _listeners = <RawDropListener>{};

  var _initialized = false;

  Offset? _offset;

  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(
      (call) async {
        try {
          return await _handleMethodChannel(call);
        } catch (e, s) {
          debugPrint('_handleMethodChannel: $e $s');
        }
      },
    );
  }

  Future<void> _handleMethodChannel(MethodCall call) async {
    switch (call.method) {
      case "entered":
        final position = (call.arguments as List).cast<double>();
        _offset = Offset(position[0], position[1]);
        _notifyEvent(DropEnterEvent(location: _offset!));
        break;
      case "updated":
        final position = (call.arguments as List).cast<double>();
        final previousOffset = _offset;
        _offset = Offset(position[0], position[1]);
        if (previousOffset == null) {
          _notifyEvent(DropEnterEvent(location: _offset!));
        } else {
          _notifyEvent(DropUpdateEvent(location: _offset!));
        }
        break;
      case "exited":
        _notifyEvent(DropExitEvent(location: _offset ?? Offset.zero));
        _offset = null;
        break;
      case "performOperation":
        final paths = (call.arguments as List).cast<String>();
        _notifyEvent(
          DropDoneEvent(
            location: _offset ?? Offset.zero,
            files: paths.map((e) => XFile(e)).toList(),
          ),
        );
        _offset = null;
        break;
      case "performOperation_linux":
        // gtk notify 'exit' before 'performOperation'.
        final text = (call.arguments as List<dynamic>)[0] as String;
        final offset = ((call.arguments as List<dynamic>)[1] as List<dynamic>).cast<double>();
        final paths = const LineSplitter().convert(text).map((e) {
          try {
            return Uri.tryParse(e)?.toFilePath() ?? '';
          } catch (error, stacktrace) {
            debugPrint('failed to parse linux path: $error $stacktrace');
          }
          return '';
        }).where((e) => e.isNotEmpty);
        _notifyEvent(DropDoneEvent(
          location: Offset(offset[0], offset[1]),
          files: paths.map((e) => XFile(e)).toList(),
        ));
        break;
      case "performOperation_web":
        final results = (call.arguments as List)
            .cast<Map>()
            .map((e) => WebDropItem.fromJson(e.cast<String, dynamic>()))
            .map((e) => XFile(
                  e.uri,
                  name: e.name,
                  length: e.size,
                  lastModified: e.lastModified,
                  mimeType: e.type,
                ))
            .toList();
        _notifyEvent(
          DropDoneEvent(location: _offset ?? Offset.zero, files: results),
        );
        _offset = null;
        break;
      default:
        throw UnimplementedError('${call.method} not implement.');
    }
  }

  void _notifyEvent(DropEvent event) {
    final reversedListeners = _listeners.toList(growable: false).reversed;
    var foundTargetListener = false;
    for (final listener in reversedListeners) {
      final isInBounds = listener.isInBounds(event);
      if (isInBounds && !foundTargetListener) {
        foundTargetListener = true;
        listener.onEvent(event);
      } else {
        listener.onEvent(DropExitEvent(location: event.location));
      }
    }

    _channel.invokeMethod('updateDroppableStatus', foundTargetListener);
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

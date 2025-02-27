import 'dart:convert';

import 'package:desktop_drop/src/drop_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'events.dart';
import 'utils/platform.dart'
    if (dart.library.js_interop) 'utils/platform_web.dart';
import 'web_drop_item.dart';

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

  Future<bool> startAccessingSecurityScopedResource(
      {required Uint8List bookmark}) async {
    Map<String, dynamic> resultMap = {};
    resultMap["apple-bookmark"] = bookmark;
    final bool? result = await _channel.invokeMethod(
        "startAccessingSecurityScopedResource", resultMap);
    if (result == null) return false;
    return result;
  }

  Future<bool> stopAccessingSecurityScopedResource(
      {required Uint8List bookmark}) async {
    Map<String, dynamic> resultMap = {};
    resultMap["apple-bookmark"] = bookmark;
    final bool result = await _channel.invokeMethod(
        "stopAccessingSecurityScopedResource", resultMap);
    return result;
  }

  Future<void> _handleMethodChannel(MethodCall call) async {
    switch (call.method) {
      case "entered":
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
        final position = (call.arguments as List).cast<double>();
        _offset = Offset(position[0], position[1]);
        _notifyEvent(DropUpdateEvent(location: _offset!));
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
            files: paths.map((e) => DropItemFile(e)).toList(),
          ),
        );
        _offset = null;
        break;
      case "performOperation_macos":
        // final paths = (call.arguments as List).cast<Map<String?, Object?>>();
        final paths = call.arguments as List;
        _notifyEvent(
          DropDoneEvent(
            location: _offset ?? Offset.zero,
            files: paths
                .map((e) => DropItemFile(
                      e["path"] as String,
                      extraAppleBookmark: e["apple-bookmark"] as Uint8List?,
                    ))
                .toList(),
          ),
        );
        _offset = null;
        break;

      case "performOperation_linux":
        // gtk notify 'exit' before 'performOperation'.
        final text = (call.arguments as List<dynamic>)[0] as String;
        final offset = ((call.arguments as List<dynamic>)[1] as List<dynamic>)
            .cast<double>();
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
          files: paths.map((e) => DropItemFile(e)).toList(),
        ));
        break;
      case "performOperation_web":
        final results = (call.arguments as List)
            .cast<Map>()
            .map((e) => WebDropItem.fromJson(e.cast<String, dynamic>()))
            .map((e) => e.toDropItem())
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

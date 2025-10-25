import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_channel.dart';
import 'window_configuration.dart';

final _windowEvent = _windowEventAsStream();

/// A listenable that notifies when the windows list changes.
/// Listen to this to be notified when windows are created or destroyed.
Stream<void> get onWindowsChanged => _windowEvent.map((call) {
      if (call.method == 'onWindowsChanged') {
        return call.method;
      }
      return null;
    }).where((event) => event != null);

/// The [WindowController] instance that is used to control this window.
class WindowController {
  WindowController._(this.windowId, this.arguments)
      : _windowChannel = WindowMethodChannel(
          'mixin.one/window_controller/$windowId',
          mode: ChannelMode.unidirectional,
        );

  final String windowId;
  final String arguments;

  final WindowMethodChannel _windowChannel;

  factory WindowController.fromWindowId(String id) =>
      WindowController._(id, '');

  static Future<WindowController> create(
      WindowConfiguration configuration) async {
    final windowId = await _channel.invokeMethod<String>(
      'createWindow',
      configuration.toJson(),
    );
    assert(windowId != null, 'windowId is null');
    assert(windowId!.isNotEmpty, 'windowId is empty');
    return WindowController._(windowId!, configuration.arguments);
  }

  static Future<WindowController> fromCurrentEngine() async {
    final definition = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getWindowDefinition');
    if (definition == null) {
      throw Exception('Failed to get window definition');
    }
    final windowId = definition['windowId'] as String;
    final windowArgument = definition['windowArgument'] as String;
    return WindowController._(windowId, windowArgument);
  }

  static Future<List<WindowController>> getAll() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getAllWindows');
    if (result == null) {
      return [];
    }
    return result.cast<Map<dynamic, dynamic>>().map((e) {
      final windowId = e['windowId'] as String;
      final windowArgument = e['windowArgument'] as String;
      return WindowController._(windowId, windowArgument);
    }).toList();
  }

  Future<void> _callWindowMethod(String method,
      [Map<String, dynamic>? arguments]) {
    assert(windowId.isNotEmpty, 'windowId is empty');
    assert(method.startsWith('window_'), 'method must start with "window_"');
    return _channel.invokeMethod(
      method,
      {
        'windowId': windowId,
        ...?arguments,
      },
    );
  }

  Future<void> show() => _callWindowMethod('window_show', {});

  Future<void> hide() => _callWindowMethod('window_hide', {});

  @optionalTypeArgs
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) =>
      _windowChannel.invokeMethod<T>(method, arguments);

  Future<void> setWindowMethodHandler(
      Future<dynamic> Function(MethodCall call)? handler) {
    assert(() {
      scheduleMicrotask(() async {
        final c = await WindowController.fromCurrentEngine();
        if (c.windowId != windowId) {
          throw FlutterError(
              'setWindowMethodHandler can only be called on the current window controller. '
              'Current windowId: ${c.windowId}, this windowId: $windowId');
        }
      });
      return true;
    }());
    return _windowChannel.setMethodCallHandler(handler);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final WindowController otherController = other as WindowController;
    return windowId == otherController.windowId &&
        arguments == otherController.arguments;
  }

  @override
  int get hashCode => windowId.hashCode ^ arguments.hashCode;

  @override
  String toString() {
    return 'WindowController(windowId: $windowId, arguments: $arguments)';
  }
}

final _channel = MethodChannel('mixin.one/desktop_multi_window');

Stream<MethodCall> _windowEventAsStream() {
  late StreamController<MethodCall> controller;
  controller = StreamController<MethodCall>.broadcast(
    onListen: () {
      _channel.setMethodCallHandler((call) async {
        controller.add(call);
      });
    },
    onCancel: () {
      _channel.setMethodCallHandler(null);
    },
  );
  return controller.stream;
}

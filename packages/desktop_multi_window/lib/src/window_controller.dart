import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_configuration.dart';

final _onWindowsChangedNotifier = ValueNotifier<int>(0);

/// A listenable that notifies when the windows list changes.
/// Listen to this to be notified when windows are created or destroyed.
Listenable get onWindowsChanged => _onWindowsChangedNotifier;

/// The [WindowController] instance that is used to control this window.
class WindowController {
  WindowController._(this.windowId, this.arguments);

  final String windowId;
  final String arguments;

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

  Future<void> invokeMethod(String method, [dynamic arguments]) =>
      _callWindowMethod('window_invoke_method', {
        'method': method,
        'arguments': arguments,
      });

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

void initializeMultiWindow() {
  debugPrint('Setting up method call handler for desktop_multi_window');
  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onWindowsChanged':
        // Handle windows changed event - just trigger notification
        _onWindowsChangedNotifier.value++;
        break;
      default:
        throw MissingPluginException('Not implemented method: ${call.method}');
    }
  });
}

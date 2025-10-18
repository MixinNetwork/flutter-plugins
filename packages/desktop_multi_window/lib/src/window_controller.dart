import 'dart:convert';

import 'package:flutter/services.dart';

import 'window_configuration.dart';

final _channel = MethodChannel('mixin.one/desktop_multi_window');

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
      jsonEncode(configuration.toJson()),
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
}

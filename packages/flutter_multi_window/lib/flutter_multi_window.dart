import 'dart:async';

import 'package:flutter/services.dart';

import 'src/window_controller.dart';
import 'src/window_controller_impl.dart';

class FlutterMultiWindow {
  static const MethodChannel _channel =
      MethodChannel('mixin.one/flutter_multi_window');

  static Future<WindowController> createWindow() async {
    final windowId = await _channel.invokeMethod<int>('createWindow');
    assert(windowId != null, 'windowId is null');
    return WindowControllerMainImpl(_channel, windowId!);
  }
}

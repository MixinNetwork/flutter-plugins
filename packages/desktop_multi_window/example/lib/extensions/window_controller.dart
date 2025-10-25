import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

extension WindowControllerExtension on WindowController {
  Future<void> doCustomInitialize() async {
    return await setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_center':
          return await windowManager.center();
        case 'window_close':
          return await windowManager.close();
        default:
          throw MissingPluginException(
              'Not implemented method: ${call.method}');
      }
    });
  }

  Future<void> center() {
    return invokeMethod('window_center');
  }

  Future<void> close() {
    return invokeMethod('window_close');
  }
}

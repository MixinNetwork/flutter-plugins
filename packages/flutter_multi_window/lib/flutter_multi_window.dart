import 'dart:async';

import 'src/window_channel.dart';
import 'src/window_controller.dart';
import 'src/window_controller_impl.dart';

export 'src/window_controller.dart';

class FlutterMultiWindow {
  static Future<WindowController> createWindow([String? arguments]) async {
    final windowId = await miltiWindowChannel.invokeMethod<int>(
      'createWindow',
      arguments,
    );
    assert(windowId != null, 'windowId is null');
    assert(windowId! > 0, 'id must be greater than 0');
    return WindowControllerMainImpl(
      windowId!,
      /* in main isolate */ true,
    );
  }
}

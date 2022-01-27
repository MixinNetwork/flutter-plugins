import 'dart:async';

import 'src/channels.dart';
import 'src/window_controller.dart';
import 'src/window_controller_impl.dart';

export 'src/window_controller.dart';

class DesktopMultiWindow {
  static Future<WindowController> createWindow([String? arguments]) async {
    final windowId = await miltiWindowChannel.invokeMethod<int>(
      'createWindow',
      arguments,
    );
    assert(windowId != null, 'windowId is null');
    assert(windowId! > 0, 'id must be greater than 0');
    return WindowControllerMainImpl(windowId!);
  }
}

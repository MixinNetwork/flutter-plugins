import 'dart:async';

import 'package:flutter/services.dart';

import 'src/channels.dart';
import 'src/window_controller.dart';
import 'src/window_controller_impl.dart';
import 'src/window_options.dart';

export 'src/window_controller.dart';
export 'src/window_options.dart';
export 'src/windows/window_options.dart';
export 'src/windows/extended_window_style.dart';
export 'src/windows/window_style.dart';
export 'src/macos/window_options.dart';
export 'src/macos/window_level.dart';
export 'src/macos/window_style_mask.dart';
export 'src/macos/window_type.dart';
export 'src/macos/window_backing.dart';
export 'src/macos/title_visibility.dart';
export 'src/macos/animation_behavior.dart';
export 'src/window_events.dart';
export 'src/macos/window_collection_behavior.dart';

class DesktopMultiWindow {
  /// Create a new Window.
  ///
  /// The new window instance will call `main` method in your `main.dart` file in
  /// new flutter engine instance with some addiotonal arguments.
  /// the arguments of `main` method is a fixed length list.
  /// ---------------------------------------------------------
  /// | index |   Type   |        description                 |
  /// |-------|----------| -----------------------------------|
  /// | 0     | `String` | the value always is "multi_window".|
  /// | 1     | `int`    | the id of the window.              |
  /// | 2     | `String` | the [arguments] of the window.     |
  /// ---------------------------------------------------------
  ///
  /// You can use [WindowController] to control the window.
  ///
  /// NOTE: [createWindow] will only create a new window, you need to call
  /// [WindowController.show] to show the window.
  static Future<WindowController> createWindow([String? arguments, WindowOptions? options]) async {
    
    final Map<String, dynamic> args = {
      if (arguments != null) 'arguments': arguments,
      if (options != null) 'options': options.toJson(),
    };
    
    final windowId = await multiWindowChannel.invokeMethod<int>(
      'createWindow',
      args,
    );
    assert(windowId != null, 'windowId is null');
    assert(windowId! > 0, 'id must be greater than 0');
    return WindowControllerImpl(windowId!);
  }

  /// Invoke method on the isolate of the window.
  ///
  /// Need use [setMethodHandler] in the target window isolate to handle the
  /// method.
  ///
  /// [targetWindowId] which window you want to invoke the method.
  static Future<dynamic> invokeMethod(int targetWindowId, String method, [dynamic arguments]) {
    return interWindowEventChannel.invokeMethod(method, <String, dynamic>{
      'targetWindowId': targetWindowId,
      'arguments': arguments,
    });
  }

  /// Add a method handler to the isolate of the window.
  ///
  /// NOTE: you can only handle this window event in this window engine isoalte.
  /// for example: you can not receive the method call which target window isn't
  /// main window in main window isolate.
  ///
  static void setMethodHandler(Future<dynamic> Function(MethodCall call, int fromWindowId)? handler) {
    if (handler == null) {
      interWindowEventChannel.setMethodCallHandler(null);
      return;
    }
    interWindowEventChannel.setMethodCallHandler((call) async {
      final fromWindowId = call.arguments['fromWindowId'] as int;
      final arguments = call.arguments['arguments'];
      final result = await handler(MethodCall(call.method, arguments), fromWindowId);
      return result;
    });
  }

  /// Get all sub window id.
  static Future<List<int>> getAllSubWindowIds() async {
    final result = await multiWindowChannel.invokeMethod<List<dynamic>>('getAllSubWindowIds');
    final ids = result?.cast<int>() ?? const [];
    assert(!ids.contains(0), 'ids must not contains main window id');
    assert(ids.every((id) => id > 0), 'id must be greater than 0');
    return ids;
  }
}

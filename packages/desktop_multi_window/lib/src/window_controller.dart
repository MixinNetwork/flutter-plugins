import 'dart:ui';

import 'package:flutter/services.dart';

import 'window_controller_impl.dart';

/// The [WindowController] instance that is used to control this window.
abstract class WindowController {
  WindowController();

  /// NOTE: you should only call this method in current window [id] isolate.
  factory WindowController.fromWindowId(int id) {
    return WindowControllerMainImpl(id, /* in main isolate */ false);
  }

  /// Close the window.
  Future<void> close();

  /// Show the window.
  Future<void> show();

  /// Hide the window.
  Future<void> hide();

  /// Set the window frame rect.
  Future<void> setFrame(Rect frame);

  /// Center the window on the screen.
  Future<void> center();

  /// Set the window's title.
  Future<void> setTitle(String title);

  /// available only on macOS.
  Future<void> setFrameAutosaveName(String name);

  void startDragging();

  Future<void> setMinSize(Size size);

  Future<void> setMaxSize(Size size);

  /// Invoke method on the isolate of the window.
  void invokeMethod(String method, [dynamic arguments]);

  /// Add a method handler to the isolate of the window.
  void setMethodHandler(void Function(MethodCall call) handler);
}

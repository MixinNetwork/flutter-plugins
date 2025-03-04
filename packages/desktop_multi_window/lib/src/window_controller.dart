import 'dart:ui';

import 'window_controller_impl.dart';
import 'window_events.dart';

/// The [WindowController] instance that is used to control this window.
abstract class WindowController {
  static final List<WindowController> _controllers = [];

  WindowController();

  factory WindowController.fromWindowId(int id) {
    final controller = _controllers.firstWhere(
      (controller) => controller.windowId == id,
      orElse: () {
        final controller = WindowControllerImpl(id);
        _controllers.add(controller);
        return controller;
      },
    );
    return controller;
  }

  factory WindowController.main() {
    return WindowController.fromWindowId(0);
  }

  /// The id of the window.
  /// 0 means the main window.
  int get windowId;

  void addListener(WindowEvents listener);

  void removeListener(WindowEvents listener);

  /// Close the window.
  Future<void> close();

  /// Show the window.
  Future<void> show();

  /// Hide the window.
  Future<void> hide();

  /// Get the window frame rect.
  Future<Rect> getFrame();

  /// Set the window frame rect.
  Future<void> setFrame(Rect frame, {bool animate = false});

  /// Get the window size.
  Future<Size> getSize();

  /// Set the window size.
  Future<void> setSize(Size size, {bool animate = false});

  /// Get the window position.
  Future<Offset> getPosition();

  /// Set the window position.
  Future<void> setPosition(Offset position, {bool animate = false});

  /// Center the window on the screen.
  Future<void> center();

  /// Set the window's title.
  Future<void> setTitle(String title);

  /// Whether the window can be resized. Available only on macOS.
  ///
  /// Most useful for ensuring windows *cannot* be resized. Windows are
  /// resizable by default, so there is no need to explicitly define a window
  /// as resizable by calling this function.
  Future<void> resizable(bool resizable);

  /// Available only on macOS.
  Future<void> setFrameAutosaveName(String name);
}

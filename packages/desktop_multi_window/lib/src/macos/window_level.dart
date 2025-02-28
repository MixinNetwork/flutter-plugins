/// Defines macOS window levels.
/// These values determine the z-ordering of windows.
enum MacOSWindowLevel {
  /// Standard window level.
  normal(0),

  /// Floating window level; appears above normal windows.
  floating(3),

  /// Modal panel level; typically used for dialog boxes.
  modalPanel(8),

  /// Submenu window level.
  subMenu(4),

  /// Main menu window level.
  mainMenu(24),

  /// Status window level.
  status(25),

  /// Popup menu window level.
  popUpMenu(101),

  /// Screen saver window level; highest level.
  screenSaver(1000);

  final int value;
  const MacOSWindowLevel(this.value);
}

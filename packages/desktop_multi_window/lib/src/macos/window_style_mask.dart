// ignore_for_file: constant_identifier_names

/// A collection of macOS window style mask constants corresponding to NSWindow.StyleMask.
/// These constants can be combined with the bitwise OR operator to configure an NSWindow or NSPanel.
///
/// Note: Some values (like `texturedBackground`) are deprecated or less commonly used,
/// and the specific bit assignments should be verified against your target macOS version.
class MacOSWindowStyleMask {
  /// A borderless window with no title bar or controls.
  /// (Equivalent to an empty set of style masks.)
  static const int borderless = 0;

  /// A window with a title bar.
  static const int titled = 1 << 0;

  /// A window with a close button.
  static const int closable = 1 << 1;

  /// A window with a minimize button.
  static const int miniaturizable = 1 << 2;

  /// A window with a resizable border.
  static const int resizable = 1 << 3;

  /// A window that supports full screen mode.
  static const int fullScreen = 1 << 4;

  /// A window with a textured background.
  /// (Deprecated in modern macOS versions but may still be available.)
  static const int texturedBackground = 1 << 5;

  // Bit 6 is unused/reserved.

  /// A utility window (often used for panels) with a smaller title bar.
  static const int utility = 1 << 7;

  /// A window with a unified title bar and toolbar.
  static const int unifiedTitleAndToolbar = 1 << 8;

  /// A panel that does not activate when clicked.
  /// (Typically used with NSPanel to prevent it from taking focus.)
  static const int nonactivatingPanel = 1 << 9;

  // Bits 10 through 14 are reserved.

  /// A window whose content view extends to cover the full window area,
  /// including the title bar (commonly used for modern fullscreen content).
  static const int fullSizeContentView = 1 << 15;
}

// ignore_for_file: constant_identifier_names

/// A collection of Windows window style constants used with CreateWindow/CreateWindowEx.
///
/// These constants correspond to the standard Windows API window styles.
class WindowsWindowStyle {
  /// Overlapped window style (no border).
  static const int WS_OVERLAPPED = 0x00000000;

  /// Popup window style.
  static const int WS_POPUP = 0x80000000;

  /// Child window style.
  static const int WS_CHILD = 0x40000000;

  /// Window is initially minimized.
  static const int WS_MINIMIZE = 0x20000000;

  /// Window is initially visible.
  static const int WS_VISIBLE = 0x10000000;

  /// Window is disabled.
  static const int WS_DISABLED = 0x08000000;

  /// Clips child windows relative to each other.
  static const int WS_CLIPSIBLINGS = 0x04000000;

  /// Excludes the area occupied by child windows.
  static const int WS_CLIPCHILDREN = 0x02000000;

  /// Window is maximized.
  static const int WS_MAXIMIZE = 0x01000000;

  /// Window has a thin-line border.
  static const int WS_BORDER = 0x00800000;

  /// Window has a dialog frame.
  static const int WS_DLGFRAME = 0x00400000;

  /// Vertical scroll bar present.
  static const int WS_VSCROLL = 0x00200000;

  /// Horizontal scroll bar present.
  static const int WS_HSCROLL = 0x00100000;

  /// Window has a system menu.
  static const int WS_SYSMENU = 0x00080000;

  /// Window has a sizing border.
  static const int WS_THICKFRAME = 0x00040000;

  /// Specifies the first control of a group.
  static const int WS_GROUP = 0x00020000;

  /// Specifies that the window is a control that can be cycled through using the TAB key.
  static const int WS_TABSTOP = 0x00010000;

  /// For overlapped windows, same as WS_GROUP.
  static const int WS_MINIMIZEBOX = 0x00020000;

  /// For overlapped windows, same as WS_TABSTOP.
  static const int WS_MAXIMIZEBOX = 0x00010000;
}
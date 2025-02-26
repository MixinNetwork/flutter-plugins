// ignore_for_file: constant_identifier_names

/// A collection of Windows extended window style constants used with CreateWindowEx.
///
/// These constants correspond to the extended window style flags in the Windows API.
class WindowsExtendedWindowStyle {
  /// Creates a window with no extended style.
  static const int NO_EX_STYLE = 0;

  /// Creates a window with a double border; typically used for dialog boxes.
  static const int WS_EX_DLGMODALFRAME = 0x00000001;

  /// The child window does not send a WM_PARENTNOTIFY message to its parent window when it is created or destroyed.
  static const int WS_EX_NOPARENTNOTIFY = 0x00000004;

  /// Specifies a topmost window.
  static const int WS_EX_TOPMOST = 0x00000008;

  /// The window accepts drag-drop files.
  static const int WS_EX_ACCEPTFILES = 0x00000010;

  /// The window should be transparent.
  static const int WS_EX_TRANSPARENT = 0x00000020;

  /// Designates a Multiple Document Interface (MDI) child window.
  static const int WS_EX_MDICHILD = 0x00000040;

  /// Creates a tool window; a window intended to be used as a floating toolbar.
  static const int WS_EX_TOOLWINDOW = 0x00000080;

  /// Specifies that the window has a border with a raised edge.
  static const int WS_EX_WINDOWEDGE = 0x00000100;

  /// Specifies that the window has a border with a sunken edge.
  static const int WS_EX_CLIENTEDGE = 0x00000200;

  /// Adds a question mark to the window's title bar.
  static const int WS_EX_CONTEXTHELP = 0x00000400;

  /// Right-aligns the window’s title bar text.
  static const int WS_EX_RIGHT = 0x00001000;

  /// Displays the window’s text in right-to-left reading order.
  static const int WS_EX_RTLREADING = 0x00002000;

  /// Places the vertical scroll bar (if present) on the left rather than the right side of the window.
  static const int WS_EX_LEFTSCROLLBAR = 0x00004000;

  /// The window is a control container that can be navigated with the TAB key.
  static const int WS_EX_CONTROLPARENT = 0x00010000;

  /// Adds a static edge border style to a window.
  static const int WS_EX_STATICEDGE = 0x00020000;

  /// Forces a top-level window onto the taskbar when visible.
  static const int WS_EX_APPWINDOW = 0x00040000;

  /// Combines WS_EX_WINDOWEDGE and WS_EX_CLIENTEDGE (value: 0x00000300).
  static const int WS_EX_OVERLAPPEDWINDOW = 0x00000300;

  /// Combines WS_EX_WINDOWEDGE, WS_EX_TOOLWINDOW, and WS_EX_TOPMOST (value: 0x00000188).
  static const int WS_EX_PALETTEWINDOW = 0x00000188;

  /// Allows the window to be a layered window.
  static const int WS_EX_LAYERED = 0x00080000;

  /// Prevents the window from inheriting the layout of its parent window.
  static const int WS_EX_NOINHERITLAYOUT = 0x00100000;

  /// Specifies that the window should have a right-to-left layout.
  static const int WS_EX_LAYOUTRTL = 0x00400000;

  /// Paints all descendants of a window in bottom-to-top painting order using double-buffering.
  static const int WS_EX_COMPOSITED = 0x02000000;

  /// A window created with this style does not become the foreground window when the user clicks it.
  static const int WS_EX_NOACTIVATE = 0x08000000;
}

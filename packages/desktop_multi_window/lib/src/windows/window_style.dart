// ignore_for_file: constant_identifier_names

enum WindowsWindowStyle {
  /// Overlapped window style (no border)
  WS_OVERLAPPED(0x00000000),

  /// Popup window style
  WS_POPUP(0x80000000),

  /// Child window style
  WS_CHILD(0x40000000),

  /// Window is initially minimized
  WS_MINIMIZE(0x20000000),

  /// Window is initially visible
  WS_VISIBLE(0x10000000),

  /// Window is disabled
  WS_DISABLED(0x08000000),

  /// Clips child windows relative to each other
  WS_CLIPSIBLINGS(0x04000000),

  /// Excludes the area occupied by child windows
  WS_CLIPCHILDREN(0x02000000),

  /// Window is maximized
  WS_MAXIMIZE(0x01000000),

  /// Window has a thin-line border
  WS_BORDER(0x00800000),

  /// Window has a dialog frame
  WS_DLGFRAME(0x00400000),

  /// Vertical scroll bar present
  WS_VSCROLL(0x00200000),

  /// Horizontal scroll bar present
  WS_HSCROLL(0x00100000),

  /// Window has a system menu
  WS_SYSMENU(0x00080000),

  /// Window has a sizing border
  WS_THICKFRAME(0x00040000),

  /// Specifies the first control of a group
  WS_GROUP(0x00020000),

  /// Specifies that the window is a control that can be cycled through using the TAB key
  WS_TABSTOP(0x00010000),

  /// For overlapped windows, same as WS_GROUP (value: 0x00020000)
  WS_MINIMIZEBOX(0x00020000),

  /// For overlapped windows, same as WS_TABSTOP (value: 0x00010000)
  WS_MAXIMIZEBOX(0x00010000);

  final int value;
  const WindowsWindowStyle(this.value);
}

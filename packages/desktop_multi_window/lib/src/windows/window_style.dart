// ignore_for_file: constant_identifier_names

/// Windows Window Styles (WS_*)
/// These values control the appearance and behavior of the window
class WindowsWindowStyle {
  /// Creates an overlapped window. An overlapped window has a title bar and a border. Same as WS_TILED
  static const int WS_OVERLAPPED = 0x00000000;

  /// Creates a pop-up window. Cannot be used with WS_CHILD
  static const int WS_POPUP = 0x80000000;

  /// Creates a child window. Cannot be used with WS_POPUP
  static const int WS_CHILD = 0x40000000;

  /// Creates a window that is initially minimized. Same as WS_ICONIC
  static const int WS_MINIMIZE = 0x20000000;

  /// Creates a window that is initially visible
  static const int WS_VISIBLE = 0x10000000;

  /// Creates a window that is initially disabled
  static const int WS_DISABLED = 0x08000000;

  /// Clips child windows relative to each other
  static const int WS_CLIPSIBLINGS = 0x04000000;

  /// Excludes the area occupied by child windows when drawing within the parent window
  static const int WS_CLIPCHILDREN = 0x02000000;

  /// Creates a window that is initially maximized
  static const int WS_MAXIMIZE = 0x01000000;

  /// Creates a window that has a title bar (includes WS_BORDER)
  static const int WS_CAPTION = 0x00C00000;

  /// Creates a window that has a thin-line border
  static const int WS_BORDER = 0x00800000;

  /// Creates a window that has a border of a style typically used with dialog boxes
  static const int WS_DLGFRAME = 0x00400000;

  /// Creates a window that has a vertical scroll bar
  static const int WS_VSCROLL = 0x00200000;

  /// Creates a window that has a horizontal scroll bar
  static const int WS_HSCROLL = 0x00100000;

  /// Creates a window that has a window menu (system menu) in its title bar
  static const int WS_SYSMENU = 0x00080000;

  /// Creates a window that has a sizing border (thick frame)
  /// This enables resizing the window by dragging the border
  static const int WS_THICKFRAME = 0x00040000;

  /// Specifies the first control of a group of controls
  static const int WS_GROUP = 0x00020000;

  /// Specifies a control that can receive keyboard focus when Tab is pressed
  static const int WS_TABSTOP = 0x00010000;

  /// Creates a window that has a minimize button
  static const int WS_MINIMIZEBOX = 0x00020000;

  /// Creates a window that has a maximize button
  static const int WS_MAXIMIZEBOX = 0x00010000;

  /// Common window style combinations

  /// Creates a standard overlapped window
  /// Combines: WS_OVERLAPPED, WS_CAPTION, WS_SYSMENU, WS_THICKFRAME, WS_MINIMIZEBOX, WS_MAXIMIZEBOX
  /// This is the most common style for main application windows
  static const int WS_OVERLAPPEDWINDOW = WS_OVERLAPPED | 
                                        WS_CAPTION | 
                                        WS_SYSMENU | 
                                        WS_THICKFRAME | 
                                        WS_MINIMIZEBOX | 
                                        WS_MAXIMIZEBOX;

  /// Creates a standard popup window with a border and system menu
  /// Combines: WS_POPUP, WS_BORDER, WS_SYSMENU
  /// Typically used for dialog boxes, message boxes, or other temporary windows
  static const int WS_POPUPWINDOW = WS_POPUP | 
                                   WS_BORDER | 
                                   WS_SYSMENU;
}
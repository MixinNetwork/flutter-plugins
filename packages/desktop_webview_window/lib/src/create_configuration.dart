/// Options that only WebView2 on Windows honours.
class WindowsWebviewOptions {
  const WindowsWebviewOptions({
    this.userDataFolder = 'webview_window_WebView2',
    this.denyCameraAndMicrophone = false,
  });

  /// WebView2 user data folder. A relative path is resolved against the
  /// executable's directory.
  final String userDataFolder;

  /// Deny every camera and microphone permission request the page (or any
  /// frame in it) makes, instead of handing it to Windows, which prompts the
  /// user on the app's behalf.
  ///
  /// The denial is not saved to the shared profile. Requires WebView2 Runtime
  /// 111.0.1661.34 or later; window creation fails on older runtimes when
  /// enabled.
  final bool denyCameraAndMicrophone;

  Map<String, Object?> toMap() => {
        'userDataFolderWindows': userDataFolder,
        'denyCameraAndMicrophone': denyCameraAndMicrophone,
      };
}

/// What the default composer shows in the window's title bar, next to the
/// system window buttons. An application composer receives the same choices
/// in `DWWComposeRequest::title_bar` and may ignore them.
class TitleBarOptions {
  const TitleBarOptions({
    this.showNavigation = true,
    this.showReload = true,
    this.showTitle = true,
    this.showHost = true,
  });

  /// Back and forward buttons.
  final bool showNavigation;

  /// The reload button, which stops the page while it loads.
  final bool showReload;

  /// The page title, or [CreateConfiguration.title] while the page has none.
  final bool showTitle;

  /// The current page's host, for example `example.com`.
  final bool showHost;

  // DWWTitleBarItem in webview_window_composer.h.
  int get _flags =>
      (showNavigation ? 1 : 0) |
      (showReload ? 2 : 0) |
      (showTitle ? 4 : 0) |
      (showHost ? 8 : 0);
}

class CreateConfiguration {
  /// Window size in logical pixels.
  final int windowWidth;
  final int windowHeight;

  /// Position of the window's top-left corner in logical pixels. Used only
  /// with [useWindowPositionAndSize]; otherwise the window is centred.
  final int windowPosX;
  final int windowPosY;

  /// The title of the window. The default composer replaces it with the
  /// page title once the page has one.
  final String title;

  /// What the default composer shows in the title bar. Applications that want
  /// another frame, or none, install a native composer.
  final TitleBarOptions titleBar;

  /// Passed unchanged to the native composer's compose callback, for example
  /// to choose a layout per window. The plugin never interprets it.
  final String? composerArguments;

  /// Place the window at [windowPosX], [windowPosY] instead of centring it.
  final bool useWindowPositionAndSize;
  final bool openMaximized;

  /// Create the window hidden, so nothing is painted until it is shown, for
  /// example through [Webview.nativeWindowHandle].
  ///
  /// On Windows `create` resolves only once WebView2 has started, which can
  /// take seconds on a cold start; a window created visible sits blank that
  /// whole time.
  final bool openHidden;

  final WindowsWebviewOptions windows;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.windowPosX = 0,
    this.windowPosY = 0,
    this.title = "",
    this.titleBar = const TitleBarOptions(),
    this.composerArguments,
    this.useWindowPositionAndSize = false,
    this.openMaximized = false,
    this.openHidden = false,
    this.windows = const WindowsWebviewOptions(),
  });

  factory CreateConfiguration.platform() => const CreateConfiguration();

  Map<String, Object?> toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
        "windowPosX": windowPosX,
        "windowPosY": windowPosY,
        "title": title,
        "titleBar": titleBar._flags,
        "composerArguments": composerArguments,
        "useWindowPositionAndSize": useWindowPositionAndSize,
        "openMaximized": openMaximized,
        "openHidden": openHidden,
        ...windows.toMap(),
      };
}

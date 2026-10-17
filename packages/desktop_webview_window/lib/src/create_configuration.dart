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

class CreateConfiguration {
  /// Window size in logical pixels.
  final int windowWidth;
  final int windowHeight;

  /// Position of the window's top-left corner in logical pixels. Used only
  /// with [useWindowPositionAndSize]; otherwise the window is centred.
  final int windowPosX;
  final int windowPosY;

  /// The title of the window.
  final String title;

  /// Show the system title bar and window buttons on macOS, Windows and Linux.
  ///
  /// Provide your own window controls and drag region when hiding it.
  final bool showSystemTitleBar;

  /// Show the default composer's native toolbar above the page. A native
  /// composer installed by the application receives it and may ignore it.
  final bool showToolbar;

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
    this.showSystemTitleBar = true,
    this.showToolbar = true,
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
        "showSystemTitleBar": showSystemTitleBar,
        "showToolbar": showToolbar,
        "composerArguments": composerArguments,
        "useWindowPositionAndSize": useWindowPositionAndSize,
        "openMaximized": openMaximized,
        "openHidden": openHidden,
        ...windows.toMap(),
      };
}

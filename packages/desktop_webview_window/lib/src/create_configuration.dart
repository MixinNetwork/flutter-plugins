class CreateConfiguration {
  final int windowWidth;
  final int windowHeight;

  /// Position of the top left point of the webview window
  final int windowPosX;
  final int windowPosY;

  /// the title of window
  final String title;

  /// Show the system title bar and window buttons on macOS, Windows and Linux.
  ///
  /// When false, toolbar top padding is omitted. The Flutter toolbar is
  /// controlled separately by WebviewTitleBarConfiguration. Provide your own
  /// window controls and drag region when hiding the system title bar.
  final bool showSystemTitleBar;

  final String userDataFolderWindows;

  final bool useWindowPositionAndSize;
  final bool openMaximized;

  /// Windows only. Create the window hidden, so nothing is painted until
  /// [Webview.setWebviewWindowVisibility] shows it.
  ///
  /// `create` resolves only once WebView2 has started, which can take seconds
  /// on a cold start; a window created visible sits blank and white all that
  /// time, and hiding it after `create` returns is too late to prevent that.
  final bool openHidden;

  /// Windows only. Deny every camera and microphone permission request the
  /// page (or any frame in it) makes, instead of handing it to Windows, which
  /// prompts the user on the app's behalf.
  ///
  /// The denial is not saved to the shared profile. Requires WebView2 Runtime
  /// 111.0.1661.34 or later; window creation fails on older runtimes when enabled.
  final bool denyCameraAndMicrophone;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.windowPosX = 0,
    this.windowPosY = 0,
    this.title = "",
    this.showSystemTitleBar = true,
    this.userDataFolderWindows = 'webview_window_WebView2',
    this.useWindowPositionAndSize = false,
    this.openMaximized = false,
    this.openHidden = false,
    this.denyCameraAndMicrophone = false,
  });

  factory CreateConfiguration.platform() => const CreateConfiguration();

  Map toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
        "windowPosX": windowPosX,
        "windowPosY": windowPosY,
        "title": title,
        "showSystemTitleBar": showSystemTitleBar,
        "userDataFolderWindows": userDataFolderWindows,
        "useWindowPositionAndSize": useWindowPositionAndSize,
        "openMaximized": openMaximized,
        "openHidden": openHidden,
        "denyCameraAndMicrophone": denyCameraAndMicrophone,
      };
}

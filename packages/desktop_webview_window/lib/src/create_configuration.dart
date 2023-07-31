import 'dart:io';

class CreateConfiguration {
  final int windowWidth;
  final int windowHeight;

  /// Position of the top left point of the webview window
  final int windowPosX;
  final int windowPosY;

  /// the title of window
  final String title;

  final int titleBarHeight;

  final int titleBarTopPadding;

  final String userDataFolderWindows;
  final bool useFullScreen;
  final bool disableTitleBar;

  final bool useWindowPositionAndSize;
  final bool openMaximized;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.windowPosX = 0,
    this.windowPosY = 0,
    this.title = "",
    this.titleBarHeight = 40,
    this.titleBarTopPadding = 0,
    this.userDataFolderWindows = 'webview_window_WebView2',
    this.useFullScreen = false,
    this.disableTitleBar = false,
    this.useWindowPositionAndSize = false,
  });

  factory CreateConfiguration.platform() {
    return CreateConfiguration(
      titleBarTopPadding: Platform.isMacOS ? 24 : 0,
    );
  }

  Map toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
        "windowPosX": windowPosX,
        "windowPosY": windowPosY,
        "title": title,
        "titleBarHeight": disableTitleBar ? 0 : titleBarHeight,
        "titleBarTopPadding": disableTitleBar ? 0 : titleBarTopPadding,
        "userDataFolderWindows": userDataFolderWindows,
        "useFullScreen": useFullScreen,
        "disableTitleBar": disableTitleBar,
        "useWindowPositionAndSize": useWindowPositionAndSize,
      };
}

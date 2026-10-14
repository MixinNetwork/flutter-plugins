# desktop_webview_window

[![Pub](https://img.shields.io/pub/v/desktop_webview_window.svg)](https://pub.dev/packages/desktop_webview_window)

Show a webview window on your flutter desktop application.

|          |       |     |
| -------- | ------- | ---- |
| Windows  | ✅     | [WebView2 SDK](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31) 1.0.4258.31 |
| Linux    | ✅    |  [WebKitGTK-4.1](https://webkitgtk.org/reference/webkit2gtk/stable/index.html) or [WebKitGTK-4.0](https://webkitgtk.org/reference/webkit2gtk/2.5.1/) |
| macOS    | ✅     |  WKWebview |

## Getting Started

1. To enable the optional webview title-bar controls, modify your `main` method.
   ```dart
   import 'package:desktop_webview_window/desktop_webview_window.dart';
   
   void main(List<String> args) async {
     WidgetsFlutterBinding.ensureInitialized();
     
     // Add this your main method.
     // used to show a webview title bar.
     if (runWebViewTitleBarWidget(args)) {
       return;
     }
   
     runApp(MyApp());
   }
   
   ```

2. launch WebViewWindow

   ```dart
     final webview = await WebviewWindow.create();
     webview.launch("https://example.com");
   ```

## Example

The example is a browser control panel with a built-in local demo page. It works
without an external website and supports multiple browser windows, navigation,
JavaScript, page messages, cookies and a per-window event log. On Windows it also
exposes hidden-window creation, media denial, visibility, activation, positioning
and DevTools.

```shell
cd packages/desktop_webview_window/example
flutter pub get
flutter run -d macos # or windows / linux
```

```text
Desktop WebView                                     [App theme]
Built-in demo / Custom URL              [Open window] [Open 3]
[x] Flutter titlebar       Windows: [ ] Hidden [ ] Deny media
+----------------------+-------------------------------------+
| Browser windows      | Navigation / JavaScript / messages   |
| Select a window      | Cookies / result / window options   |
+----------------------+-------------------------------------+
| Event log: all windows or a selected window                 |
+------------------------------------------------------------+
```

The app theme affects the control panel. Each browser's Flutter titlebar still
runs in its own engine, using `runWebViewTitleBarWidget` and the existing
`TitleBarWebViewController` / `TitleBarWebViewState` APIs. Disable the Flutter
titlebar to give its space to the web content.

## Tests

Run package tests from the package directory and example tests from `example/`:

```shell
flutter test
cd example
flutter pub get
flutter analyze
flutter test
```

All native integration scenarios register through `example/integration_test/app_test.dart`.
Scenario modules live under `integration_test/src/` and have no separate entry
points. macOS uses a driver adapter; Windows runs the same suite directly:

```shell
# From example/, on the matching platform:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d macos
flutter test integration_test/app_test.dart -d windows --timeout 5m
```

macOS coverage includes real WKWebView navigation, independent browser/titlebar
state, titlebar back/forward/reload/stop/close, DOM input, resizing and repeated
close/recreate. Native inspection and titlebar command fixtures live only in the
example's Debug runner. Windows coverage includes WebView2 POST bodies,
navigation replacement/cancellation (including redirects and cached history),
hidden/maximized visibility and non-persistent media denial.

The repository CI selects affected package/platform targets from
`.github/integration-tests.json`, validates the example, runs the shared suite and
uploads its log. A target may optionally provide a driver. Keep new scenarios in
the suite instead of adding scenario-specific CI jobs. Linux has no registered
native integration suite yet. DOM scripting and fake media devices do not prove
physical input delivery or real camera/microphone behavior.

## linux requirement

In Ubuntu/Debian:
```shell
sudo apt-get install libwebkit2gtk-4.1-0 libwebkit2gtk-4.1-dev libsoup-3.0-0 libsoup-3.0-dev
```

In Fedora/RPM:
```shell
sudo dnf install webkit2gtk4.1 webkit2gtk4.1-devel libsoup3 libsoup3-devel
```

## Windows

### Requirement

The backend of desktop_webview_window on Windows is WebView2, which requires **WebView2 Runtime** installed.

[WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2) is ship in box with Windows11, but
it may not installed on Windows10 devices. So you need consider how to distribute the runtime to your users.

See more: https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution

For convenience, you can use `WebviewWindow.isWebviewAvailable()` check whether the WebView2 is available.

### Attention

The default user data folder of WebView2 is `your_exe_file\WebView2`, which is not a good place to store user data.

eg. if the application is installed in a read-only directory, the application will crash when WebView2 try to write data.

you can use `WebviewWindow.create()` to create a webview with a custom user data folder.

```dart
final webview = await WebviewWindow.create(
  configuration: CreateConfiguration(
    userDataFolderWindows: 'your_custom_user_data_folder',
  ),
);
```

### Window and media options

`CreateConfiguration(openHidden: true)` creates a Windows WebView without
showing its window. Show it later with `setWebviewWindowVisibility(true)` or
`bringToForeground(maximized: true)`.

`CreateConfiguration(denyCameraAndMicrophone: true)` denies camera and microphone
requests for that window without saving the denial in the shared profile.
This option requires WebView2 Runtime 111.0.1661.34 or later. Window creation
fails on older runtimes when this option is enabled. Both options default to
`false`.

### Windows regression tests

Run from `example/` on Windows with WebView2 Runtime installed:

```powershell
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--use-fake-device-for-media-stream'
flutter test integration_test/windows_webview_test.dart -d windows --timeout 5m
```

The tests use local pages, temporary profiles, and fake media devices. They do
not require a physical camera or microphone.

The bundled Windows SDK headers, loader DLL, and import library come from
Microsoft.Web.WebView2 SDK 1.0.4258.31.

## License

see [LICENSE](./LICENSE)

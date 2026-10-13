# desktop_webview_window

[![Pub](https://img.shields.io/pub/v/desktop_webview_window.svg)](https://pub.dev/packages/desktop_webview_window)

Show a webview window on your flutter desktop application.

|          |       |     |
| -------- | ------- | ---- |
| Windows  | ✅     | [WebView2 SDK](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31) 1.0.4258.31 |
| Linux    | ✅    |  [WebKitGTK-4.1](https://webkitgtk.org/reference/webkit2gtk/stable/index.html) or [WebKitGTK-4.0](https://webkitgtk.org/reference/webkit2gtk/2.5.1/) |
| macOS    | ✅     |  WKWebview |

## Getting Started

1. Run the main application and optional browser titlebars on one engine:

   ```dart
   import 'package:desktop_webview_window/desktop_webview_window.dart';

   void main() {
     runWebviewWindowApp(const MyApp());
   }
   ```

   For a custom titlebar, pass `titleBarBuilder`. Startup arguments and the old
   `runWebViewTitleBarWidget` hook are no longer used.

2. launch WebViewWindow

   ```dart
     final webview = await WebviewWindow.create();
     webview.launch("https://example.com");
   ```

## One application engine (Flutter 3.47.6 or newer)

The main application and every browser titlebar use the same Flutter engine and
Dart isolate. `runWebviewWindowApp` replaces `runApp` with a multi-view root.
Each browser has a separate Flutter view above its native WebView2, WKWebView or
WebKit content. Closing a browser removes only its titlebar view.

Application initialization runs once. There is no dedicated titlebar engine,
startup-argument dispatch, cross-engine message bridge, or renderer fallback.
Titlebar state and commands are delivered within the same Dart isolate. Each
widget retains its own state; static/global variables are shared with the main
application. A titlebar's Flutter view ID and browser ID are distinct.

To install inherited dependencies above both the main application and titlebars,
use `runWidget` with `WebviewWindowApp` as the multi-view child. Dependencies
inside `MyApp` remain scoped to the main view.

Using ordinary `runApp` without this root creates browsers without Flutter
titlebars. `CreateConfiguration(titleBarHeight: 0)` also omits the titlebar.

### macOS runner setup

macOS must enable multi-view before its first controller is created. In
`macos/Runner/MainFlutterWindow.swift`, import the plugin and replace the default
controller construction:

```swift
import desktop_webview_window

let flutterViewController = try! DesktopWebviewWindowPlugin.createMainViewController()
```

Keep the existing window assignment and `RegisterGeneratedPlugins` call after
this line. The helper creates the application's only engine and main controller.
Windows and Linux reuse their normal runner engine without a runner change.

Windows uses runtime-resolved borrowing APIs; macOS uses guarded internal
multi-view selectors. Future Flutter upgrades require native validation.
Legacy macOS plugins that assume an implicit controller need separate checking.
See [design and validation](doc/shared_titlebar_engine.md).

### Linux rendering

Linux uses the public `fl_view_new_for_engine` API on the main application engine.
X11/GLX rendering has related upstream failures, including
[Flutter #186577](https://github.com/flutter/flutter/issues/186577).
See [the Linux investigation](doc/linux_shared_titlebar_engine.md) for evidence.

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
flutter test integration_test/app_test.dart -d windows --timeout 5m
```

The tests use local pages, temporary profiles, and fake media devices. They do
not require a physical camera or microphone.

The bundled Windows SDK headers, loader DLL, and import library come from
Microsoft.Web.WebView2 SDK 1.0.4258.31.

## License

see [LICENSE](./LICENSE)

## Repeatable macOS integration test

All platform scenarios register through the package's single application test
entry point, `example/integration_test/app_test.dart`. Files under
`integration_test/src/` contain scenarios only, with no additional `main()`.

From `example`, run the native shared-titlebar regression with:

```sh
flutter drive -d macos --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart
```

This launches real WKWebViews and the dedicated multi-view toolbar engine. It
checks independent navigation and toolbar state, toolbar commands, native page
DOM behavior, resize, duplicate/rapid close, zero-height mode, and reuse after all
windows close. `flutter drive` preserves the secondary engine's entry arguments;
`flutter test` wraps `main()` and does not support this multi-engine test target.
The existing integration CI matrix includes this target. Native keyboard/pointer
focus and visual rendering still need a short manual check when the SDK changes.
See [Shared titlebar engine](doc/shared_titlebar_engine.md) for design, validation results, and platform limits.

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

## Shared titlebar engine (Flutter 3.47.6 or newer)

Windows and macOS now create **one dedicated Flutter engine/isolate for all
webview titlebars**, lazily when the first titlebar is needed. Your application's
main Flutter engine remains independent. Each browser keeps its native WebView2,
WKWebView or WebKit widget below a non-overlapping Flutter titlebar.
`WebviewWindow.create`, `Webview` and `runWebViewTitleBarWidget` keep their existing
calling conventions; no change from `runApp` to `runWidget` is required in your
application. Keep the entrypoint hook above **before** application initialization
and `runApp`. A custom `builder` is used for every titlebar in the shared isolate.

- Every titlebar has its own Flutter view ID and browser controller ID. These are
  different namespaces; the package routes state and commands by browser ID.
- Static variables in a custom titlebar builder are now shared across titlebars
  on Windows/macOS. Use per-widget state for window-specific values.
- Calling `create` without the entrypoint hook now creates a browser without a
  Flutter titlebar instead of accidentally starting another copy of your app.
  `CreateConfiguration(titleBarHeight: 0)` also skips titlebar engine creation.
- Closing one browser removes only its view. The dedicated engine stays alive
  until the owning plugin is disposed, so closing/reopening all browser windows
  does not restart the titlebar isolate. No per-window plugins are auto-registered
  into that isolate; this retains the old titlebar plugin-registration contract.
- The minimum Flutter version is deliberately raised to 3.47.6. Windows uses a
  runtime-resolved internal exported controller constructor; macOS uses guarded
  internal multi-view activation. These are stock-engine APIs, not a custom
  engine fork, but they are **not a stable public embedding contract**. Future
  Flutter upgrades require native validation. Unsupported runtimes return an
  error rather than attaching a second owning controller to the same engine.

### Linux renderer safety

Linux retains its existing **per-window titlebar engines by default**. Rapid
secondary-view destruction/recreation reproduced `GLX BadAccess` with the stock
OpenGL renderer in a standalone shared-engine experiment, including with Impeller
disabled. A software-renderer pass does not establish production GPU safety.
The existing Linux close/use-after-free bug is fixed independently of this gate.

For explicitly experimental validation only:

```dart
final webview = await WebviewWindow.create(
  configuration: const CreateConfiguration(
    useSharedTitleBarEngineLinux: true,
  ),
);
```

Do not enable this flag for production until your renderer/platform has been
validated. It does not force software rendering or hide a fallback. This change
does not implement an embedded Flutter `WebView` widget or transparent-hole
composition. See [validation and manual regression plan](doc/shared_titlebar_engine.md)
for what has and has not been tested.

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

## Repeatable macOS integration test

From `example`, run the native shared-titlebar regression with:

```sh
flutter drive -d macos --driver=test_driver/integration_test.dart --target=integration_test/shared_engine_test.dart
```

This launches real WKWebViews and the dedicated multi-view toolbar engine. It
checks independent navigation and toolbar state, toolbar commands, native page
DOM behavior, resize, duplicate/rapid close, zero-height mode, and reuse after all
windows close. `flutter drive` preserves the secondary engine's entry arguments;
`flutter test` wraps `main()` and does not support this multi-engine test target.
The existing integration CI matrix includes this target. Native keyboard/pointer
focus and visual rendering still need a short manual check when the SDK changes.
See [Shared titlebar engine](doc/shared_titlebar_engine.md) for design, validation results, and platform limits.

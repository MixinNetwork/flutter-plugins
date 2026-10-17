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

   For a custom titlebar, pass `titleBar: WebviewTitleBarConfiguration(...)`.
   Its `builder(context, webview, state)` receives the browser handle and current
   navigation state. Startup-argument dispatch is not needed.

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

Applications that already manage Flutter views use the composable host instead
of the convenience root:

```dart
runWidget(
  WebviewTitleBarHost(
    titleBar: WebviewTitleBarConfiguration(
      height: 44,
      builder: (context, webview, state) => IconButton(
        onPressed: state.canGoBack ? webview.back : null,
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    child: const MyMultiWindowApp(), // Creates its own views/windows.
  ),
);
```

The host renders only browser toolbar views. Application windows remain owned
by `MyMultiWindowApp`. Install one host per engine above windows that may close
independently. Shared inherited dependencies belong above the host. Dependencies
inside a particular window remain scoped to that window.

`WebviewWindow.create()` follows the host defaults. A `titleBar` argument replaces
them for that browser. A null theme continues to follow the host theme;
`setTitleBarTheme(null)` restores the window configuration or host theme.
Builder and theme changes update existing toolbars. Height, padding and enabled
state are applied when creating a browser.

To use ordinary `runApp` without Flutter toolbar views, explicitly disable them:

```dart
final webview = await WebviewWindow.create(
  titleBar: const WebviewTitleBarConfiguration.none(),
);
```

Requesting a Flutter toolbar without a mounted host throws a `StateError` instead
of silently hiding it. `showSystemTitleBar` remains independent of the Flutter
toolbar. Configure Flutter toolbars through `WebviewTitleBarConfiguration`.
See [Migration](#migration) for removed APIs and their replacements.

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
Applications already using Flutter multi-window startup keep their existing
engine and use `WebviewTitleBarHost`; the plugin borrows that engine without
requiring a main view or calling this helper.

Windows and ordinary Linux runners need no change. A headless Linux runner calls
`desktop_webview_window_plugin_attach_engine(engine)` after generated plugin
registration. Include
`desktop_webview_window/desktop_webview_window_plugin.h` for that function.
This explicitly supplies the existing engine because the public Linux registrar
has no engine getter when its view is null.

Windows uses runtime-resolved borrowing APIs; macOS uses guarded internal
multi-view selectors. Future Flutter upgrades require native validation.
Legacy macOS plugins that assume an implicit controller need separate checking.
See [design and validation](doc/shared_titlebar_engine.md).

### Linux rendering

Linux uses the public `fl_view_new_for_engine` API on the main application engine.
X11/GLX rendering has related upstream failures, including
[Flutter #186577](https://github.com/flutter/flutter/issues/186577).
See [the Linux investigation](doc/linux_shared_titlebar_engine.md) for evidence.

## Migration

The old titlebar APIs have been removed. Existing callers must migrate to
`WebviewTitleBarConfiguration`; they are no longer available as deprecated
aliases.

### Titlebar builders and themes

Move the root titlebar parameters into `titleBar`. This applies to both
`runWebviewWindowApp` and `WebviewWindowApp`.

| Removed API | Replacement |
| --- | --- |
| `titleBarBuilder` | `titleBar.builder`, with `(context, webview, state)` arguments |
| `titleBarBackgroundColor` | `titleBar.backgroundColor` |
| `titleBarTheme` | `titleBar.theme` |
| `TitleBarWebViewController.of(context)` | The `webview` passed to the builder |
| `TitleBarWebViewState.of(context)` | The `state` passed to the builder |

Before:

```dart
runWebviewWindowApp(
  const MyApp(),
  titleBarTheme: ThemeData.dark(),
  titleBarBackgroundColor: Colors.black,
  titleBarBuilder: (context) {
    final controller = TitleBarWebViewController.of(context);
    final state = TitleBarWebViewState.of(context);
    return IconButton(
      onPressed: state.canGoBack ? controller.back : null,
      icon: const Icon(Icons.arrow_back),
    );
  },
);
```

After:

```dart
runWebviewWindowApp(
  const MyApp(),
  titleBar: WebviewTitleBarConfiguration(
    theme: ThemeData.dark(),
    backgroundColor: Colors.black,
    builder: (context, webview, state) => IconButton(
      onPressed: state.canGoBack ? webview.back : null,
      icon: const Icon(Icons.arrow_back),
    ),
  ),
);
```

Use `state.isLoading`, `state.canGoBack`, `state.canGoForward`, and `state.url`
for navigation state. Call `webview.back()`, `forward()`, `reload()`, `stop()`,
or `close()` for browser commands. Outside a titlebar builder, listen to
`webview.navigationState` for updates.

### Titlebar dimensions and omission

The `titleBarHeight` and `titleBarTopPadding` constructor parameters and getters
have been removed from `CreateConfiguration`. Keep native window options there;
pass Flutter toolbar options through `WebviewWindow.create(titleBar: ...)`.

Before:

```dart
final webview = await WebviewWindow.create(
  configuration: const CreateConfiguration(
    windowWidth: 1024,
    titleBarHeight: 48,
    titleBarTopPadding: 12,
  ),
);
```

After:

```dart
final webview = await WebviewWindow.create(
  configuration: const CreateConfiguration(windowWidth: 1024),
  titleBar: const WebviewTitleBarConfiguration(height: 48, topPadding: 12),
);
```

To set dimensions for all browsers, put them in the host's `titleBar`
configuration instead. A per-window configuration replaces the host defaults;
include any custom builder or background color that window should retain.
A null theme continues to follow the host theme.

Replace `CreateConfiguration(titleBarHeight: 0)` with:

```dart
final webview = await WebviewWindow.create(
  titleBar: const WebviewTitleBarConfiguration.none(),
);
```

Ordinary `runApp` no longer silently omits Flutter toolbars. Explicitly pass
`.none()` when no toolbar host is mounted. To keep Flutter toolbars, start with
`runWebviewWindowApp`, or mount `WebviewTitleBarHost` in an application that
already manages its own views. `showSystemTitleBar` still controls the native
system titlebar independently.

For applications migrating from the older separate-engine implementation,
remove the `runWebViewTitleBarWidget(args)` startup hook and its early return.
Initialize the application once with `runWebviewWindowApp`. On macOS, also
follow the [runner setup](#macos-runner-setup) above.

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

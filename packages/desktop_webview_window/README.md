# desktop_webview_window

[![Pub](https://img.shields.io/pub/v/desktop_webview_window.svg)](https://pub.dev/packages/desktop_webview_window)

Show a webview window on your flutter desktop application.

|          |       |     |
| -------- | ------- | ---- |
| Windows  | ✅     | [WebView2 SDK](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31) 1.0.4258.31 |
| Linux    | ✅    |  [WebKitGTK-4.1](https://webkitgtk.org/reference/webkit2gtk/stable/index.html) or [WebKitGTK-4.0](https://webkitgtk.org/reference/webkit2gtk/2.5.1/) |
| macOS    | ✅     |  WKWebview |

## Getting Started

```dart
import 'package:desktop_webview_window/desktop_webview_window.dart';

final webview = await WebviewWindow.create();
await webview.launch('https://example.com');
```

The window's native title bar carries back, forward, reload/stop, the page
title and its host, next to the system window buttons. Choose the items with
`CreateConfiguration(titleBar: TitleBarOptions(...))`, or install a
[native composer](#window-layout) to lay the window out yourself. No runner
changes or startup hooks are needed.

## Talking to the page

Every page gets the same `window.desktopWebview` object on macOS, Windows and
Linux. Messages carry any JSON-encodable value.

```js
// In the page
window.desktopWebview.postMessage('login', {token: 'abc'});
window.desktopWebview.addEventListener('theme', data => applyTheme(data));
```

```dart
webview.addJavaScriptHandler('login', (data) => print(data)); // {token: abc}
await webview.postMessage('theme', {'dark': true});
```

`evaluateJavaScript` returns the decoded result (`Map`, `List`, `String`, `num`,
`bool` or `null`).

## Navigation decisions

`setOnUrlRequestCallback` runs before every top-level navigation, including
redirects, while a callback is installed. The navigation waits for it, so the
callback answers synchronously. Return false to cancel; a callback that throws
allows the navigation. `launch(url, triggerOnUrlRequestEvent: false)` skips the
decision for that navigation.

`webview.navigationState` reports `canGoBack`, `canGoForward`, `isLoading`, and
the current page's `url` and `title`. Native composers receive the same state.

## Controlling the window

The plugin owns each browser window but does not move, show or focus it after
creation. `webview.nativeWindowHandle` returns the native window — `HWND` on
Windows, `NSWindow*` on macOS and `GtkWindow*` on Linux — for a window library
or your own FFI code:

```dart
import 'dart:ffi';
import 'package:nativeapi/nativeapi.dart';

final window = Window.createWithNativeWindow(
    Pointer.fromAddress(webview.nativeWindowHandle))!;
window.show();
window.focus();
unawaited(webview.onClose.then((_) => window.dispose()));
```

The handle is valid until `onClose` completes and is 0 afterwards. Borrow it:
do not destroy or close the window through it, replace its delegate or window
procedure, or keep it beyond `onClose`. Use `webview.close()` to close the
window. A source review of `nativeapi-core` (commit `ead6a88`) found that
wrapping a window does not destroy it on any desktop platform; its ownership
semantics are not documented upstream, so verify again when upgrading. Its
macOS `setNonActivating(true)` changes the window class and disables keyboard
input in borderless browser windows.

Creation-time placement stays in `CreateConfiguration`: `openHidden`,
`openMaximized`, and `useWindowPositionAndSize` with `windowPosX`/`windowPosY`.
On macOS and Windows, `CreateConfiguration(brightness: Brightness.dark)` applies
the appearance before the window is shown, including its startup background.
The default, null, follows the system. Use `setBrightness` to change it later.
Linux follows the application's GTK theme.

## Platform support

| Feature | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Page messaging, navigation decisions, script results | ✅ | ✅ | ✅ |
| `nativeWindowHandle`, `openHidden`, `openMaximized`, position | ✅ | ✅ | ✅ |
| `openDevToolsWindow` | ❌ Safari Web Inspector (debug builds) | ✅ | ✅ |
| `setBrightness` | ✅ | ✅ | ❌ |
| `setPromptHandler` | ✅ | ❌ | ❌ |
| `WindowsWebviewOptions` | — | ✅ | — |

Calling an unsupported operation throws `UnsupportedError`. Operations return
futures that complete once native code has applied them and fail with a
`PlatformException` when it reports an error.

## Window layout

The plugin owns each browser window and its WebView. A *composer* decides what
else the window contains and where the WebView sits. Without one, the default
composer merges navigation into the window's title bar, like a Chrome app
window:

```
macOS    ● ● ●  ‹ › ⟳  Page title          (NSToolbar, unified)
                       example.com
Windows  ← → ⟳  Page title  example.com      ─ □ ✕   (custom drawn)
Linux    [‹|›] ⟳      Page title       ✕      (GtkHeaderBar)
                      example.com
```

Each item can be hidden:

```dart
CreateConfiguration(
  titleBar: TitleBarOptions(
    showNavigation: true, // back and forward
    showReload: true,     // reload, or stop while loading
    showTitle: true,      // page title, or CreateConfiguration.title
    showHost: false,      // host of the current URL
  ),
)
```

The window title follows the page title, so the Dock, taskbar and window
switchers name the page even when the title bar hides it.

To use a different layout (a sidebar, an overlay, your own toolbar, no title
bar at all), install a
native composer from the runner before the first browser is created. It
receives the window and a view containing the WebView, and may arrange them
however it likes:

```c
#include <desktop_webview_window/webview_window_composer.h>

static DWWComposeResult compose(void* user, const DWWComposeRequest* request) {
  if (request->arguments == NULL) return DWW_COMPOSE_DEFAULT;  // Default title bar.
  GtkWidget* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_box_pack_start(GTK_BOX(row), my_sidebar(request->browser), FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(row), GTK_WIDGET(request->webview_view), TRUE, TRUE, 0);
  gtk_container_add(GTK_CONTAINER(request->window), row);
  gtk_widget_show_all(row);
  return DWW_COMPOSE_HANDLED;
}

static const DWWComposer composer = {NULL, compose, navigation_changed, NULL, closing};
dww_set_composer(&composer);  // In the runner, before the first create.
```

Controls call `dww_browser_go_back`, `dww_browser_reload`, `dww_browser_close`
and friends with the browser ID; `navigation_changed` delivers the navigation
state. `CreateConfiguration(composerArguments: ...)` is passed to `compose`
unchanged, so one composer can lay out different windows differently. A
composer that returns `DWW_COMPOSE_DEFAULT` hands that window to the default
composer for its whole lifetime. `request->title_bar` carries the
`TitleBarOptions` flags (`DWW_TITLE_BAR_*`) for composers that want to honor
them. A composer may restyle the window, for example to remove its title bar;
on Windows it handles window messages by subclassing the window with
`SetWindowSubclass`.

The header documents the window and view types per platform and the rules for
borrowed pointers, closing from inside callbacks, and Windows resizing. The
example runner's `linux/test_composer.cc` is a complete composer. See
[the design](doc/native_window_composer.md) for the full contract.

The composer is native code, so a Flutter UI inside a browser window means
creating your own Flutter view there. On Linux X11 that is subject to
[Flutter #186577](https://github.com/flutter/flutter/issues/186577), which is
why the plugin itself no longer renders Flutter toolbars.

## Migration

0.4.0 is a breaking release. The APIs below were removed rather than
deprecated.

### Browser API changes

| Removed API | Replacement |
| --- | --- |
| `registerJavaScriptMessageHandler(name, (name, body) {...})` | `addJavaScriptHandler(name, (data) {...})`; the page calls `window.desktopWebview.postMessage(name, data)` |
| `unregisterJavaScriptMessageHandler` | `removeJavaScriptHandler` |
| `postWebMessageAsString` / `postWebMessageAsJson` | `postMessage(name, data)`; the page listens with `window.desktopWebview.addEventListener(name, ...)` |
| `addOnWebMessageReceivedCallback` and related | `addJavaScriptHandler` |
| `isNavigating` | `navigationState.value.isLoading` |
| `setOnHistoryChangedCallback` | Listen to `navigationState` |
| `moveWebviewWindow`, `setWebviewWindowVisibility`, `bringToForeground`, `getPositionalParameters` | `nativeWindowHandle` with a window library; see [Controlling the window](#controlling-the-window) |
| `CreateConfiguration(userDataFolderWindows:, denyCameraAndMicrophone:)` | `CreateConfiguration(windows: WindowsWebviewOptions(userDataFolder:, denyCameraAndMicrophone:))` |
| `clearAll(userDataFolderWindows:)` | `clearAll(windows: WindowsWebviewOptions(...))` |

Behavior changes:

- `launch`, `close`, `setBrightness`, `setOnUrlRequestCallback`,
  `addScriptToExecuteOnDocumentCreated` and `openDevToolsWindow` return futures
  and report native errors.
- `evaluateJavaScript` returns `Future<Object?>` with the decoded value instead
  of a JSON string.
- `setOnUrlRequestCallback` can cancel navigations on every platform.
- On Linux, browser windows are independent top-level windows, as on macOS and
  Windows, instead of transient children of the application window: they no
  longer stay above it, and open centred on the screen.
- Pages from the old bridges must switch to `window.desktopWebview`;
  `window.webkit.messageHandlers.<name>` and `chrome.webview` messages are no
  longer forwarded.
- macOS cookies now report `expires`, `secure`, `httpOnly` and `sessionOnly`.
- Browser IDs (`Webview.id`) are unique per process.

### Titlebars

Browser windows no longer run Flutter. Remove the `runWebViewTitleBarWidget(args)`
startup hook and its early return, and delete the titlebar widget:

| Removed API | Replacement |
| --- | --- |
| `runWebViewTitleBarWidget(args, builder: ...)` | The default native title bar, or a [native composer](#window-layout) |
| `TitleBarWebViewController.of(context)` | `dww_browser_*` in a composer, or the `Webview` in Dart |
| `TitleBarWebViewState.of(context)` | `navigation_changed` in a composer, or `webview.navigationState` in Dart |
| `CreateConfiguration(titleBarHeight: 0)` | `CreateConfiguration(titleBar: TitleBarOptions(showNavigation: false, showReload: false))` |
| `CreateConfiguration(titleBarTopPadding: ...)` | Composer layout |

Navigation controls drawn by the main application window can keep using
`webview.back()`, `forward()`, `reload()`, `stop()`, `close()` and
`webview.navigationState`.

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
    windows: WindowsWebviewOptions(userDataFolder: 'your_custom_user_data_folder'),
  ),
);
```

### Window and media options

`CreateConfiguration(openHidden: true)` creates the window without showing it,
so nothing is painted while WebView2 starts. Show it later through
`nativeWindowHandle`; WebView2 resumes rendering when its window becomes
visible.

`WindowsWebviewOptions(denyCameraAndMicrophone: true)` denies camera and microphone
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

## Integration tests

All platform scenarios register through the package's single application test
entry point, `example/integration_test/app_test.dart`. Files under
`integration_test/src/` contain scenarios only, with no additional `main()`.

From `example`:

```sh
flutter test integration_test/app_test.dart -d linux
```

The suite launches real WebViews and checks page messaging, navigation
decisions, script results and the native window handle. On Linux it also
drives the example runner's test composer: default and application-owned
layouts side by side, resize, title bar buttons, closing from each composer
callback, and repeated close/recreate. Native keyboard/pointer focus and visual
rendering still need a short manual check.

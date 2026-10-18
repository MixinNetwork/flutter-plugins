# desktop_webview_window example

A browser control panel with a built-in local demo page. It works without an
external website and supports multiple browser windows, an address bar,
navigation, page messages, JavaScript, cookies and a per-window activity log.

```shell
cd packages/desktop_webview_window/example
flutter pub get
flutter run -d macos # or windows / linux
```

```text
Desktop WebView                                      (● Runtime ready)
+------------------+---------------------------------------------------+
| [+ New window]   | Page title                          [x Close]     |
|                  | [<] [>] [R]  [ http://127.0.0.1:5123/?id=2    ]   |
| ● Browser 1      | [Messages] [JavaScript] [Cookies] [Window]        |
| ● Browser 2   <  |   controls, then this panel's latest result       |
+------------------+---------------------------------------------------+
| > Activity · 14       [This window | All]                    [clear] |
+----------------------------------------------------------------------+
```

New window opens a dialog that chooses the page (built-in demo or a URL), the
layout and the system titlebar. Layouts:

- Toolbar: the plugin's default composer with its native toolbar.
- Sidebar composer: the example runner's own native composer
  (`composerArguments: 'sidebar'`), with controls left of the page.
- None: the page fills the window.

Windows also offers hidden creation and camera/microphone denial. Below 760
logical pixels the window list becomes a dropdown. The Window panel sets the
per-window appearance on macOS and Windows and opens DevTools on Windows and
Linux. The app theme menu in the header switches the control panel and all open
browser windows between System, Light and Dark. New windows start in the current
app theme, including their startup background before the first page loads.
Changing the app theme also replaces any per-window appearance override. On
Linux this uses the example process's GTK theme; it does not change the desktop
settings.

## Tests

From this example directory:

```shell
flutter pub get
flutter analyze
flutter test
```

Run package tests from `packages/desktop_webview_window/` with `flutter test`.

### Integration tests

All native integration scenarios register through `integration_test/app_test.dart`.
Scenario modules live under `integration_test/src/` and have no separate `main()`
or test application entry points. macOS uses a driver adapter; Windows and Linux
run the same suite directly:

```shell
# From example/, on the matching platform:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d macos
flutter test integration_test/app_test.dart -d linux
```

For the Windows command and fake media setup, see [Windows](#windows).

The suite launches real WebViews and checks page messaging, navigation
decisions, script results and the native window handle.

macOS coverage includes real WKWebView navigation, independent browser/titlebar
state, titlebar back/forward/reload/stop/close, DOM input, resizing and repeated
close/recreate. Native geometry inspection lives only in the example's Debug
runner; titlebar commands are exercised directly through the shared test host.
Windows coverage includes WebView2 POST bodies,
navigation replacement/cancellation (including redirects and cached history),
hidden/maximized visibility and non-persistent media denial.

On Linux the suite also drives the example runner's test composer: default and
application-owned layouts side by side, resize, title bar buttons, closing from
each composer callback, and repeated close/recreate. Native keyboard/pointer
focus and visual rendering still need a short manual check. DOM scripting and
fake media devices do not prove physical input delivery or real
camera/microphone behavior.

The repository CI selects affected package/platform targets from
[`.github/integration-tests.json`](../../../.github/integration-tests.json),
validates the example, runs the shared suite and uploads its log. A target may
optionally provide a driver. Keep new scenarios in the suite instead of adding
scenario-specific CI jobs. Linux has no registered CI target yet; run its suite
locally using the command above.

### Windows

Run from this example directory on Windows with WebView2 Runtime installed:

```powershell
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--use-fake-device-for-media-stream'
flutter test integration_test/app_test.dart -d windows --timeout 5m
```

The tests use local pages, temporary profiles, and fake media devices. They do
not require a physical camera or microphone.

Windows builds fetch Microsoft.Web.WebView2 SDK 1.0.4258.31 and statically link
the loader for the target architecture. The SDK is reused in the application's
build directory until `flutter clean`; see [Windows setup](../README.md#windows).

The SDK download/cache checks run on any host with Python 3.9+ and CMake:

```shell
# From the package directory:
python3 tool/test_webview2_sdk.py -v
```

These use a local HTTP server and cover build-local reuse, downloading again
after deleting the build directory, hash verification and
target architecture selection. They do not replace Windows build/runtime tests.

### macOS sandbox

The macOS example runs in the App Sandbox, like a shipped application. Its
entitlements allow outgoing and loopback connections (each test serves its
pages from `127.0.0.1`) and user-selected files. Keep the sandbox on when
running the suite: the tests must not touch anything outside the example's
container.

Page dialogs and file panels open as sheets. Tests inspect and end them through
the runner's `webview_example/native_test` channel (`sheet`, `endSheet`); a
panel is only ever cancelled. Choosing a file and saving a download are not
automated. Inside the sandbox, WebKit can write a download only to a location
the user picked in the panel, so a location set by a test fails with
"Operation not permitted"; outside it, the panel ignores the test's folder and
saves to the last folder the user chose. Check uploads and downloads by hand.

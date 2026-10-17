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
Linux.

## Tests

From this example directory:

```shell
flutter pub get
flutter analyze
flutter test
```

Run package tests from `packages/desktop_webview_window/` with `flutter test`.

All native integration scenarios register through `integration_test/app_test.dart`.
Scenario modules live under `integration_test/src/` and have no separate entry
points. macOS uses a driver adapter; Windows runs the same suite directly:

```shell
# From example/, on the matching platform:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d macos
flutter test integration_test/app_test.dart -d windows --timeout 5m
```

macOS coverage includes real WKWebView navigation, independent browser/titlebar
state, titlebar back/forward/reload/stop/close, DOM input, resizing and repeated
close/recreate. Native geometry inspection lives only in the example's Debug
runner; titlebar commands are exercised directly through the shared test host.
Windows coverage includes WebView2 POST bodies,
navigation replacement/cancellation (including redirects and cached history),
hidden/maximized visibility and non-persistent media denial.

The repository CI selects affected package/platform targets from
`.github/integration-tests.json`, validates the example, runs the shared suite and
uploads its log. A target may optionally provide a driver. Keep new scenarios in
the suite instead of adding scenario-specific CI jobs. Linux has no registered
native integration suite yet. DOM scripting and fake media devices do not prove
physical input delivery or real camera/microphone behavior.

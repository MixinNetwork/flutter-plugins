# desktop_webview_window example

A browser control panel with a built-in local demo page. It works
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

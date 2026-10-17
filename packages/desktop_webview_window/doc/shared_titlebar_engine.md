# Single-engine titlebars: design and validation

## Ownership and startup

The runner owns one application Flutter engine and its main view. Browser windows
own additional titlebar view controllers borrowing that engine. The plugin owns
only their routing registry. It never starts or shuts down another engine.

Ordinary applications start with `runWebviewWindowApp(MyApp())`. Its
`WebviewWindowApp` resolves only the runner-owned main view and delegates toolbar
composition to `WebviewTitleBarHost`. Applications that already own their views
mount that host directly with `runWidget`. The host renders its application child
without waiting for a main view, and joins native toolbar descriptors with the
browser handles returned by `create`.

Inside an existing view the host composes side views through `ViewAnchor`;
at a non-rendering root it uses `ViewCollection`. Only the plugin's own view IDs
are mounted. There is no startup dispatch, secondary entrypoint, event replay,
or command broadcast. Builders receive the real `Webview` and its current
`WebviewNavigationState` directly.

Native WebViews remain the browser content, below the non-overlapping titlebar.
Native keyboard/pointer behavior is unchanged by the ownership migration.

## Native transport

All Dart/native communication uses FFI, following desktop_drop. `src/` holds
the C contract (`desktop_webview_window_ffi.h`), compiled into each platform's
plugin (Darwin through forwarders in its SwiftPM/CocoaPods target):

- RPC: Dart opens the bridge with `PlatformDispatcher.engineId`; each plugin
  instance matches its own engine (macOS by messenger identity through the
  guarded engine lookup, Windows by messenger, Linux by FlEngine pointer).
  Calls and events are StandardMethodCodec payloads posted to a Dart port.
  A new isolate (hot restart) closes the previous port and drops late replies.
- Navigation decisions: Dart installs a `NativeCallable.isolateLocal`. Native
  code calls it synchronously from macOS `decidePolicyFor`, WebView2
  `NavigationStarting` and WebKitGTK `decide-policy`, only after checking that
  the current thread owns the root isolate. Otherwise navigation is allowed.
- Native windows: browser IDs and window pointers live in a process-wide
  registry, so `nativeWindowHandle` is a synchronous lookup. Windows are
  unregistered before they are destroyed.
- Page messaging: one injected script (`lib/src/js_bridge.dart`) defines
  `window.desktopWebview` over `webkit.messageHandlers.desktopWebview` or
  `chrome.webview`. Messages are JSON strings `{name, data}`.

Run `dart run tool/ffigen.dart` after changing the header; it regenerates the
Dart bindings and the Darwin header copy.

## Titlebar host calls

The titlebar host's calls share the bridge with browser calls:

- `initialize`: attach the application's engine without requiring a main view.
  Windows and macOS receive the actual `dart:ui` engine ID. macOS guards its stock
  engine lookup and verifies the messenger before borrowing the engine.
- `getMainView`: used only by the ordinary-app convenience root. macOS keeps a
  weak registration for main controllers created by its runner helper.
- `getViews`: snapshot of `{viewId, webViewId, titleBarTopPadding}`.
- `viewsChanged` (event): invalidate the snapshot.

Browser creation waits for host initialization when a Flutter toolbar is
requested. Without a host it fails explicitly; `WebviewTitleBarConfiguration.none()`
creates a native browser without that prerequisite. Native metrics and snapshots
can arrive in either order. A descriptor is mounted only when both its Flutter
view and browser handle exist. Browser IDs are distinct from Flutter view IDs.
Navigation state is held once in the browser handle, including before its toolbar
mounts. Layout configuration applies at creation; builder and theme updates apply
to existing toolbar views.

Closing a browser withdraws its routing record and destroys only its view.
Closing every browser leaves the application engine and main view running.
Plugin teardown detaches browser views without destroying the runner's engine.

## Platform contracts

- Linux: `fl_view_new_for_engine` borrows the application engine. Ordinary
  runners supply it through their registrar view. Headless runners explicitly call
  `desktop_webview_window_plugin_attach_engine` after registering plugins. No
  private object layout or engine-ID-to-pointer conversion is used. The optional
  parent view is tracked weakly so browser creation can outlive that window.
- Windows: runtime-resolved `FlutterDesktopEngineForId` and
  `FlutterDesktopEngineCreateViewController` borrow the application's engine.
  The runner retains its existing implicit view 0. The plugin never uses the
  constructor that transfers engine ownership.
  Browser windows do not forward their messages to the engine's top-level
  window delegates; those belong to the application's own windows.
- macOS: the runner calls
  `DesktopWebviewWindowPlugin.createMainViewController()` before registering
  plugins for ordinary applications. It enables multi-view before creating the
  first controller, starts the main engine, and creates the main view. Existing
  multi-window applications keep their own startup. The host resolves their
  engine by ID and needs no helper-created main controller. Plugin registries
  remove only their toolbar views through guarded internal selectors.

Flutter 3.47.7 / Dart 3.13.5 is the validation SDK. Windows/macOS still depend on
in-progress embedding APIs. Symbol guards cannot promise future ABI stability.
macOS plugins that assume `registrar.view` or an implicit controller may need
adaptation for a multi-view main application.

## Regression checks

Package tests cover missing-host errors, explicit toolbar omission, initialization
ordering and cancellation on unmount, composition with application-owned views
without an implicit view, anchored composition, browser/view routing, retained
application state, shared navigation state, per-window builder/theme overrides,
convenience-root builders, duplicate close and close before native create completes.
They also cover the bridge contract through a fake transport: page messages,
`postMessage`, decoded script results, error propagation, synchronous
navigation decisions, prompt replies, brightness overrides, and host
replacement versus duplicate hosts.

The portable Windows harness verifies that a pre-existing application engine
and view 0 survive browser create/close/reopen, that no engine is created or
destroyed, and that the plugin's borrowed properties struct matches Flutter's
internal header. This is ownership validation, not GUI rendering.

From the package:

```sh
flutter analyze --no-pub
flutter test --no-pub
./windows/tests/run_shared_toolbar_engine_test.sh /path/to/flutter
```

From `example`:

```sh
flutter drive -d macos --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart --dart-define=WEBVIEW_TEST_WINDOWING=true
flutter run -d linux -t lib/shared_engine_smoke.dart --dart-define=SMOKE_AUTORUN=true
```

`WEBVIEW_TEST_WINDOWING=true` enables the SDK's experimental windowing guard
only inside the integration fixture. Stable tooling otherwise rejects that
feature flag. This scenario uses `flutter drive` so the fixture can install a
binding that forwards the actual native engine ID; ordinary `flutter test`
preinstalls a dispatcher with synthetic engine ID 1. Existing scenarios continue
to support `flutter test` when that opt-in is absent. The shared SDK scenario
creates application-owned windows alongside browser toolbars, closes one
application window, and closes/reopens the browser without replacing the host.

The macOS integration scenario compares the native engine ID with the main
isolate's actual engine ID and verifies routing, navigation, DOM interactions,
resize, twenty close/recreate rounds and reopen after every browser is closed.
The smoke example also supports Windows and macOS and uses loopback test pages.
`SMOKE_NO_TITLEBAR_ROOT=true` exercises ordinary `runApp` without titlebars
on Windows/Linux with their unmodified runners. A macOS runner configured for
multi-view must continue to use the multi-view Dart root.

Native lifecycle checks do not prove physical keyboard/pointer delivery,
accessibility, long-running memory behavior or application shutdown. Linux X11
and Wayland must be reported independently. See the Linux investigation for
historical renderer failures; no per-window engine implementation is retained.

## Earlier single-engine validation on 2026-10-13

These results predate the composable-host refactor and do not validate its new
interfaces.

Flutter 3.47.7 / Dart 3.13.5 was used on macOS, Windows and Ubuntu 22.04 WSL.
The first complete remote single-engine code snapshot was
`20261013T100032-31e3c3fc9284`. Its logs remain under
`~/.codex/remote-flutter-tests/20261013T100032-31e3c3fc9284/`.

- Package analysis passed. Nine package tests passed locally, on Windows and
  on WSL (exit 0).
- The portable Windows ownership/routing harness passed: no engine creation or
  destruction, and application view 0 retained after every titlebar was removed.
- macOS native integration passed (driver exit 0), including equality with the
  main isolate's actual engine ID, native navigation/DOM/resize and 20 rounds.
- Windows Debug build and the automatic 20-round native smoke passed. The
  existing navigation/visibility/media-policy integration suite also passed
  (three tests, exit 0). The smoke used the remote runner's interactive task
  transport with its command pointed at the smoke target; it was not the
  three-test integration suite despite the transport job's integration label.
- WSL Debug build passed. Native Wayland completed the 20-round smoke and exited
  0. X11 reproduced GLX BadAccess and exited on SIGTRAP (-5).
- A macOS smoke application successfully hot reloaded. An earlier idle launch
  lost its connection before reload, without a new native crash report.

The final root also retains surviving titlebars when the native main view is
removed. A package regression exercises that case separately from preserving
the main subtree across browser close/recreate.

The smoke's automatic mode exits the process after its result; it does not prove
normal native teardown with outstanding windows. Release, real keyboard/pointer
acceptance, physical Linux GPU combinations, accessibility, and sustained memory
use were not validated. macOS logs retain the previously observed frame-time
clamping diagnostic. No Flutter engine source or SDK installation was modified.

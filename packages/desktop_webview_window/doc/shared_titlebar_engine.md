# Single-engine titlebars: design and validation

## Ownership and startup

The runner owns one application Flutter engine and its main view. Browser windows
own additional titlebar view controllers borrowing that engine. The plugin owns
only their routing registry. It never starts or shuts down another engine.

Dart starts once with `runWebviewWindowApp(MyApp())`. Its `WebviewWindowApp` root
uses `runWidget` and `ViewCollection` to mount the main application alongside each
titlebar's `View` and `MaterialApp`. There is no startup-argument dispatch or
secondary Dart entrypoint. Static state is shared with the application; titlebar
widget state remains browser-local.

Native WebViews remain the browser content, below the non-overlapping titlebar.
Native keyboard/pointer behavior is unchanged by the ownership migration.

`desktop_webview_window/titlebars` belongs to the application engine:

- `initialize`: attach the application's engine and return its native main view
  ID. Windows receives the actual `dart:ui` engine ID, not the test binding's
  simulated identifier. macOS identifies the runner's controller through a weak
  registration keyed by the engine messenger.
- `getViews`: snapshot of `{viewId, webViewId, titleBarTopPadding}`.
- `viewsChanged`: invalidate the snapshot.

The root waits for initialization before mounting the application. Native metrics
and snapshots can arrive in either order. Only titlebar descriptors matching a
registered Flutter view are mounted. A synthetic implicit view with no native
macOS controller must not be mistaken for the main window.

Browser state and toolbar commands use local Dart listeners. The old native
cross-engine broadcast channels are removed. Browser IDs remain distinct from
Flutter view IDs. Late widget readiness replays the latest browser state.

Closing a browser withdraws its routing record and destroys only its view.
Closing every browser leaves the application engine and main view running.
Plugin teardown detaches browser views without destroying the runner's engine.

## Platform contracts

- Linux: `fl_view_new_for_engine` borrows the existing main view's engine. There
  is no hidden bootstrap window or additional implicit owner view.
- Windows: runtime-resolved `FlutterDesktopEngineForId` and
  `FlutterDesktopEngineCreateViewController` borrow the application's engine.
  The runner retains its existing implicit view 0. The plugin never uses the
  constructor that transfers engine ownership.
- macOS: the runner calls
  `DesktopWebviewWindowPlugin.createMainViewController()` before registering
  plugins. It enables multi-view before creating the first controller, starts
  the main engine, and creates the main view. Plugin registries borrow this
  engine and remove explicit views through guarded internal selectors.

Flutter 3.47.7 / Dart 3.13.5 is the validation SDK. Windows/macOS still depend on
in-progress embedding APIs. Symbol guards cannot promise future ABI stability.
macOS plugins that assume `registrar.view` or an implicit controller may need
adaptation for a multi-view main application.

## Regression checks

Package tests cover no-root/zero-height creation, initialization ordering,
same-isolate fan-out and unsubscribe, separate browser/view IDs, main subtree
preservation across titlebar close/recreate, replay of only current browser
state, duplicate close and close before native create completes.

The portable Windows harness verifies that a pre-existing application engine
and view 0 survive browser create/close/reopen and registry disposal. It also
asserts that no engine is created/destroyed and no native message relay is
registered by the titlebar code. This is ownership validation, not GUI rendering.

From the package:

```sh
flutter analyze --no-pub
flutter test --no-pub
./windows/tests/run_shared_toolbar_engine_test.sh /path/to/flutter
```

From `example`:

```sh
flutter drive -d macos --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart
flutter run -d linux -t lib/shared_engine_smoke.dart --dart-define=SMOKE_AUTORUN=true
```

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

## Validation on 2026-10-13

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

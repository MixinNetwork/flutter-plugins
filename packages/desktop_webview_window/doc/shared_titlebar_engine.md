# Shared titlebar engine: design and validation

## Ownership and compatibility

The application's normal engine owns its plugin and browser sessions. The plugin
lazily owns one separate titlebar engine, running the existing main entrypoint
with `web_view_title_bar shared`. That entrypoint uses `runWidget` internally,
reconciles `ViewCollection` against native snapshots, and builds a separate
MaterialApp for each registered Flutter view. Native WebViews remain the browser
content and retain native keyboard/pointer handling.

A dedicated engine preserves the existing `main(List<String>)` hook and avoids
requiring consumers to replace their main `runApp` with a multi-view root. This
means one application engine **plus** one titlebar engine, not one engine total.
Custom titlebar static state is shared; widget state remains view-local.

`desktop_webview_window/titlebars` belongs only to the titlebar engine:

- `getViews`: snapshot of `{viewId, webViewId, titleBarTopPadding}`
- `viewsChanged`: invalidate the snapshot
- view-list/metrics changes and native snapshots may arrive in either order;
  only descriptors matching a currently registered Flutter view are mounted

The existing `webview_message/client_channel` routes browser state and toolbar
commands. One dispatcher multicasts incoming messages to live titlebar widgets;
widgets filter by browser ID and unsubscribe before disposal. URL-only changes
also notify custom builders. A native view ID is never used as a browser ID.

Windows controllers borrow the dedicated engine. The old public constructor that
transfers engine ownership must not be reused for multiple views. macOS enables
multi-view before the first controller and starts its engine before adding views.
Windows also retains a hidden implicit view 0; browser windows use explicit
views only. Linux's experimental path retains a realized implicit owner view because the
public secondary-view API requires an already-running non-headless engine.

## SDK and risk boundary

Reference runtime: Flutter 3.47.6, framework
`5fc346839b5d0eef006ed8404392afb4dfae428d`, engine
`692136cb6582dbfc5af3fb33c2515a069f2f66d0`.
No engine source changes or rebuilt engine are required.

macOS and Windows rely on internal embedding entrypoints in that stock runtime.
Symbol/selector guards detect missing entrypoints, not every possible future ABI
or behavior change. The minimum SDK cannot promise all future versions are
compatible. Native accessibility, plugins requiring an implicit view, and
platform input/focus integration need separate validation.

Linux shared-engine support is an explicit opt-in and remains experimental.
A standalone stock-engine probe failed rapid secondary destroy/recreate under
GLX with both Impeller enabled and disabled. Software rendering passed 20 rounds,
which is diagnostic evidence only. Keeping the implicit view alive was already
part of that probe and is not a demonstrated fix. Default Linux windows continue
to use the legacy per-window-engine renderer.

## Automated checks

Package-local Flutter tests cover malformed entry arguments, primary hook
registration, live-listener fan-out/unsubscription, snapshot/browser-ID routing,
late events after removal, close/recreate state isolation, duplicate close,
close-before-create-response, no-hook configuration, and URL-only state updates.

Run from this package with Flutter 3.47.6 or newer:

```sh
flutter pub get
flutter analyze
flutter test
```

In the monorepo, dependency resolution follows its existing pub workspace. A
standalone copy may remove only `resolution: workspace` from its pubspec for
isolated checks. Do not commit generated lockfiles solely for this refactor.

## Current validation

Replayed onto upstream `bee5a1e2cf59ace59aac88c1780a55817e5f8b07`, preserving the
released 0.3.1 platform fixes. Independently validated on 2026-10-13 with Flutter
3.47.7 / Dart 3.13.5 and Xcode 27.0 on Apple Silicon:

- Package and example analysis: no issues
- Eleven package unit/widget tests: passed
- Original example Release build and lifecycle smoke Debug build: passed
- macOS native integration scenario: passed with driver exit code 0
- Native smoke: twenty close/recreate rounds, including zero height, duplicate
  close, immediate close and reopening after all views are removed: passed
- Default toolbar back/forward/reload, real keyboard input and native button
  interaction: manually confirmed
- Portable Windows engine ownership/routing harness on macOS: passed
- Integration CI target selection/manifest regression tests: eight passed
- CI for `a49a704`: macOS native integration passed; Windows native build and
  the existing WebView2 navigation/visibility/media-policy regressions passed
- Windows shared-toolbar GUI/input acceptance and Linux native build/runtime:
  not run in this validation
- Release runtime, isolated CocoaPods plugin integration, accessibility and
  long-running memory/DPI acceptance: not run

The plugin built through Flutter's generated Swift Package dependency graph;
the example host still retains CocoaPods configuration. Runtime logs included
Flutter's `Reported frame time is older than the last one; clamping` diagnostic,
without an observed crash or interaction failure. This diagnostic remains an
open observation, not a resolved engine issue.

From `example`, run the repeatable native macOS regression:

```sh
flutter drive -d macos --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart
```

This launches real WKWebViews and the dedicated toolbar engine. It verifies
engine/view identity, mounted toolbar state, navigation isolation, production
controller commands through the cross-engine relay, DOM input/button behavior,
native resize, duplicate/rapid close and engine reuse after all windows close.
DOM focus checks do not assert real keyboard or pointer delivery. The integration
scenario uses a custom toolbar builder; default controls have separate widget
and manual coverage.

Use `flutter drive` for this target: `flutter test` wraps `main()` and discards
the secondary engine's startup arguments. Debug-only native diagnostics expose
engine/view identity; the example's Debug fixture resizes windows. Neither adds
a public Dart API or a Release diagnostics path. The existing CI matrix runs
this scenario through an optional driver, alongside its original Windows target.

Earlier recovery-archive logs are historical evidence only and are not counted
as acceptance of this replay. In particular, their partial Linux zero-toolbar
run does not establish Linux renderer safety.

## Runnable native smoke target

From `example`, run on the desired platform (replace `linux` with `windows` or
`macos`):

```sh
flutter run -d linux -t lib/shared_engine_smoke.dart
```

The target provides native-input windows and a 20-round close/recreate sequence,
including closing the first browser while others survive, duplicate close,
zero-height toolbar, and reopening after all browsers close. It serves self-contained
pages from a loopback HTTP server. A lifecycle PASS does not replace visual/input
or native renderer-log inspection.

To test no entrypoint hook, add `--dart-define=SMOKE_NO_TITLEBAR_HOOK=true`.
For explicitly experimental Linux shared-view reproduction only, add
`--dart-define=SMOKE_SHARED_LINUX=true`; expect the documented GLX risk.

## Native regression plan (all platforms)

1. Run the example normally and open three browsers with distinct URLs/titles.
2. Exercise back/forward/reload/stop in each; verify only that browser changes.
3. Type into native web inputs and move focus between browser and toolbar.
4. Resize/minimize/restore and test the correct content/titlebar boundaries.
5. Close the first-created, middle and last browser in different orders. Check
   surviving windows and the main application remain functional.
6. Reopen after all browsers close; toolbar isolate static state should survive
   on shared-engine platforms, while per-window widget state starts fresh.
7. Repeat create/close immediately, including before WebView2 initialization
   completes; check every create/onClose settles and no late callback touches a
   disposed host. Repeat 20 or more times with at least one survivor.
8. Repeat with height zero and with no hook. No toolbar engine should be started.
9. Repeat application shutdown while browsers/initialization are outstanding.
10. Repeat Debug and Release and inspect engine/controller counts and memory.

Linux: run this suite on the default fallback first, then opt in on a noncritical
local build. Test X11/Wayland and actual hardware GPU separately. Never report a
software-only pass as GLX safety. macOS: verify both native and programmatic close,
CocoaPods and SPM. Windows: test a fresh user-data folder and unavailable runtime.

## Related issue scope

- #497: Linux destroy callback must not read its owner after the callback erases
  the owning unique_ptr. Cleanup/notification precede final ownership removal.
- #511: no-hook/zero-height mode avoids starting unnecessary toolbar engines.
  This implementation is independently developed; no contributor patch is copied.
- #366/#367: Windows asynchronous creation and early-close handling are in scope;
  do not consider the historical reports fully resolved without native repro QA.
- #510: added the missing SwiftPM FlutterFramework dependency; native SPM
  resolution/build still needs macOS validation.
- #406: macOS programmatic and native close share one idempotent path; historical
  report resolution remains subject to native repro QA.
- #457/#478: related Linux teardown symptoms are not automatically resolved by
  fixing one proven use-after-free.
- #254/#200 request embedded widget functionality and are not implemented here.
- #326/#418/#176 and unrelated permission/navigation behavior are out of scope.

A draft PR is for cross-platform review and validation, not a release assertion.

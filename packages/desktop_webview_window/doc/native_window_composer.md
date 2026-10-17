# Native window composer: design

Status: implemented on Linux, macOS and Windows. Supersedes the
single-engine titlebar design in
[shared_titlebar_engine.md](shared_titlebar_engine.md) and
[linux_shared_titlebar_engine.md](linux_shared_titlebar_engine.md).

## Motivation

The 0.4.0 branch renders browser toolbars as additional Flutter views borrowing
the application's engine. On Linux X11 a second `FlView` on one engine crashes
([flutter/flutter#186577](https://github.com/flutter/flutter/issues/186577)).
Current evidence points at the engine's rendering context management. This
design removes the dependency on that path instead of working around it; it
does not claim that no plugin-side mitigation could exist. Keeping the design
would also keep its costs on every platform: runner changes (`createMainViewController()`,
`desktop_webview_window_plugin_attach_engine`), in-progress embedder APIs on
Windows/macOS, and a Dart host that must be mounted before `create`.

This design moves window composition out of Flutter and out of the plugin's
fixed layout. The plugin owns the native window, the WebView and their control.
The application decides what else the window contains and where the WebView
sits, through a native composer callback. The plugin ships a default composer
with a native toolbar, so applications that do not care need no native code.

## Responsibilities

| Plugin | Application composer |
|---|---|
| Creates and destroys the native window | Inserts the WebView view anywhere in the window |
| Owns the WebView, its delegates and handlers | Adds, removes and lays out its own views |
| Navigation decisions, JS bridge, cookies | Draws any toolbar, sidebar or overlay it wants |
| Navigation state, control functions | Reacts to navigation state changes |
| Default composer (native toolbar) | Optionally delegates some windows to the default |

The application never receives the WebView object itself (`WKWebView`,
`WebKitWebView`, `ICoreWebView2*`). It receives a container view that holds the
WebView, so it can move and nest the view freely without being able to replace
the delegates the plugin depends on.

## Native contract

One C ABI for all platforms, declared in
`src/include/desktop_webview_window/webview_window_composer.h`. Each platform
build exposes that directory to the runner (Linux: a public include directory
of the plugin target) and compiles the shared dispatch in
`src/composer_runtime.cc`. Window and view pointers are `void*`, with the
concrete types listed below.

The composer is native-to-native only. Dart and native code talk over one
method channel, `desktop_webview_window`; the earlier FFI bridge existed to
route calls between engines and is removed together with the shared engine.

```c
typedef struct {
  int64_t browser;          // Same value as Webview.id in Dart.
  void* window;             // Borrowed top-level window.
  void* webview_view;       // Borrowed WebView container view.
  const char* arguments;    // CreateConfiguration.composerArguments, UTF-8, may be NULL.
  int32_t show_toolbar;     // CreateConfiguration.showToolbar.
} DWWComposeRequest;

typedef struct {
  int64_t browser;
  int32_t can_go_back;
  int32_t can_go_forward;
  int32_t is_loading;
  const char* url;          // Borrowed for the duration of the call, may be NULL.
  const char* title;        // Document title, may be NULL.
} DWWNavigationState;

typedef enum {
  DWW_COMPOSE_DEFAULT = 0,  // The default composer owns this window.
  DWW_COMPOSE_HANDLED = 1,  // The application composer owns this window.
} DWWComposeResult;

typedef struct {
  void* user;
  // Required. Called once per browser, before the window is first shown.
  DWWComposeResult (*compose)(void* user, const DWWComposeRequest* request);
  // Optional. Called on every navigation state change, after compose.
  void (*navigation_changed)(void* user, const DWWNavigationState* state);
  // Optional. Windows only: the window's client area changed, in physical
  // pixels. Use GetDpiForWindow(window) for the scale.
  void (*layout)(void* user, int64_t browser, int32_t width, int32_t height);
  // Optional. Called once before the window and its views are destroyed.
  void (*closing)(void* user, int64_t browser);
} DWWComposer;

// Copies the struct. NULL restores the default composer. Affects browsers
// created afterwards; call it from the runner before the first create.
void dww_set_composer(const DWWComposer* composer);

// Control. Return zero when the browser is unknown, closing or closed.
int32_t dww_browser_go_back(int64_t browser);
int32_t dww_browser_go_forward(int64_t browser);
int32_t dww_browser_reload(int64_t browser);
int32_t dww_browser_stop(int64_t browser);
int32_t dww_browser_close(int64_t browser);
```

macOS adds a thin Swift wrapper over the same ABI
(`DesktopWebviewWindowPlugin.setComposer(_:)` taking a protocol with the same
four methods). It does not add behavior.

### Per-window ownership

The result of `compose` decides which composer owns that window for its whole
lifetime:

- `DWW_COMPOSE_DEFAULT`: the application must not have touched the window or
  `webview_view`. The plugin runs the default composer, and every later
  `navigation_changed`, `layout` and `closing` for that browser goes to the
  default composer only. The application composer never hears about the browser
  again.
- `DWW_COMPOSE_HANDLED`: every later callback for that browser goes to the
  application composer.

A custom composer therefore only tracks the windows it handled and never
forwards callbacks to the default implementation. Ownership is fixed at
`compose`; there is no way to hand a window over afterwards. The default
composer is not otherwise exposed.

### Concrete types

| | `window` | `webview_view` | State on entry to `compose` |
|---|---|---|---|
| macOS | `NSWindow*` | `NSView*` container | Window has an empty `contentView`; view is not in the hierarchy |
| Linux | `GtkWindow*` | `GtkWidget*` container | Window has no child; view is not parented |
| Windows | `HWND` top-level | `HWND` child of `window` | View is a hidden child; plugin keeps WebView2 bounds equal to it |

On every platform `compose` places `webview_view` and may add any other views.
If `compose` returns without placing it (macOS/Linux: not in the window's
hierarchy; Windows: never sized), the plugin makes it fill the window.

Constraints on the application:

- `webview_view` stays inside its own window. Reparenting across windows is not
  supported.
- Do not destroy `window` or `webview_view`; use `dww_browser_close`. Views the
  application added are destroyed with the window by the native hierarchy;
  release application state in `closing`.
- Do not replace the window's delegate (macOS) or window procedure (Windows).
  On Windows, top-level resize arrives through `layout`. For a window the
  application handled, a composer without `layout` gets `webview_view` filling
  the client area. Windows owned by the default composer use its own layout.
- Pointers are borrowed. Do not use them after `closing`.

### Lifecycle and threading

```
Dart create ─▶ native window + WebView created ─▶ browser registered
            ─▶ compose(request)
            ─▶ navigation_changed(initial state)
            ─▶ window shown (unless openHidden)
            ─▶ Dart create() completes
            ─▶ ... navigation_changed ... layout (Windows) ...
close       ─▶ state = closing
            ─▶ closing(browser) ─▶ browser unregistered ─▶ window destroyed
            ─▶ state = closed ─▶ Dart Webview.onClose completes
```

All callbacks run on the platform main thread. The composer is process-wide
and survives Dart hot restart, since it lives in the runner.

### Close semantics

Each browser moves through `composing → open → closing → closed`. A close
request is any of: `dww_browser_close`, Dart `Webview.close()`, the user
closing the window, or `clearAll` on Windows/Linux.

- **Idempotent.** The first request moves the browser to `closing`. Later
  requests are no-ops, including requests made from inside `closing`.
- **Deferred inside callbacks.** While any composer callback for a browser is
  running (`compose`, `navigation_changed`, `layout`, `closing`), a close
  request only records the transition; teardown runs after the outermost
  callback returns. The plugin holds a strong reference to the browser object
  for the duration of each callback dispatch, so no platform may free it while
  composer code is on the stack. This replaces the current Linux behavior of
  removing the window object synchronously on close.
- **No callbacks after closing.** Once a browser is `closing`, the plugin
  delivers no further `navigation_changed` or `layout`, and every
  `dww_browser_*` control call returns zero. `closing` is delivered exactly
  once, to the window's owner (see per-window ownership).
- **Close during `compose`.** The plugin skips the initial
  `navigation_changed` and never shows the window, then tears down normally:
  `closing` is still delivered, because the composer may already have
  allocated state for the window. Dart `create()` completes successfully with a
  `Webview` whose `onClose` has already completed and whose control methods
  fail as they do on any closed browser. This matches the current
  close-before-create-completes behavior, and guarantees that every native
  create resolves its Dart request exactly once and every returned `Webview`
  completes `onClose`.
- **Errors before `compose`.** If the native window or WebView cannot be
  created, `compose` is never called and Dart `create()` fails with a
  `PlatformException`; no `closing` is delivered.

## Default composer

A vertical layout: a native toolbar on top, `webview_view` below. With
`show_toolbar == 0`, `webview_view` fills the window.

```
┌──────────────────────────────────────────┐
│  ←  →  ⟳/✕   Document title              │  native, ~40 px
├──────────────────────────────────────────┤
│                webview_view              │
└──────────────────────────────────────────┘
```

| Platform | Toolbar |
|---|---|
| macOS | `NSStackView` of `NSButton`s with SF Symbols |
| Linux | `GtkBox` of `GtkButton`s with symbolic icons, above the WebView |
| Windows | Child window with GDI owner-drawn buttons, following system dark mode |

Buttons are icon-only, without text labels or tooltips, so the plugin carries
no localized strings. The document title is page content and is shown as is.

On macOS the toolbar sits at the top of the content area. When the system
titlebar is hidden it may end up beneath the traffic lights; that is accepted as
long as both stay operable, and the exact placement can be tuned later.

Buttons call the same `dww_browser_*` functions and update from
`DWWNavigationState`, so the default composer exercises the public contract.
Appearance follows the window's appearance, which `Webview.setBrightness`
already controls on macOS and Windows. Styling is intentionally not
configurable; applications that want another look write a composer.

## Dart API changes

Removed:

- `runWebviewWindowApp`, `WebviewWindowApp`, `WebviewTitleBarHost`
- `WebviewTitleBarConfiguration`, `WebviewTitleBarBuilder`
- `WebviewWindow.create(titleBar:)`
- `Webview.setTitleBarTheme`

Added:

- `WebviewNavigationState.title`: the document title, the same value the
  native composer receives.

Changed:

- `WebviewNavigationState.url` is the current page's URL, the same value the
  native composer receives, instead of the most recently requested URL. Native
  code sends the whole state in one `onNavigationStateChanged` event.
- `OnUrlRequestCallback` stays synchronous and `setOnUrlRequestCallback`
  returns a future. Native code asks Dart only while a callback is installed
  (`setUrlRequestEnabled`). WebKitGTK (a referenced policy decision) and macOS
  (the decision handler) hold the navigation until the `onUrlRequest` channel
  reply. WebView2's `NavigationStarting` has no deferral, so Windows uses a
  small FFI decider, the same pattern as `desktop_drop`: Dart registers a
  `NativeCallable.isolateLocal` listener and a `ReceivePort`. With merged
  platform and UI threads, native code calls the listener directly after
  checking that the thread owns the isolate; otherwise it posts the request
  and blocks the platform thread until Dart replies (500 ms timeout). No
  listener, no reply, an error or a throwing callback allows the navigation.
- `nativeWindowHandle` comes from the `create` reply instead of a synchronous
  native lookup. A reply with `closed: true` yields a browser whose `onClose`
  has completed.

Added to `CreateConfiguration`:

- `String? composerArguments`: passed to `compose` unchanged. The plugin never
  interprets it; applications typically use it to choose a layout per window.
- `bool showToolbar = true`: read by the default composer.

Unchanged: `Webview` control methods, JS bridge, `setBrightness`, cookies,
`clearAll`. Browser creation no longer
waits for a host and never fails because one is missing.

## Native code removed

- macOS: `TitleBarViews.swift`, `createMainViewController()`, multi-view setup.
- Linux: `title_bar_views.*`, `desktop_webview_window_plugin_attach_engine`.
- Windows: `flutter_view.*`, engine/view-controller borrowing, and
  `tests/shared_toolbar_engine_test.cc`.
- Bridge calls `initialize`, `getMainView`, `getViews` and event `viewsChanged`.
- The FFI bridge: `src/desktop_webview_window_ffi.*`, `src/dart_bridge_api.*`,
  the generated Dart bindings and `tool/ffigen.dart`, plus each platform's
  `ffi_transport.h`.

Runners need no plugin-specific changes unless they install a composer.

## Migration

From 0.3.2:

- Delete the `runWebViewTitleBarWidget(args)` dispatch in `main`. Browser
  windows no longer start a Flutter engine.
- Replace `TitleBarWebViewController`/`TitleBarWebViewState` toolbars with
  either the default native toolbar or a native composer.
- `clearAll(userDataFolderWindows:)` becomes
  `clearAll(windows: WindowsWebviewOptions(userDataFolder: ...))`.

For flutter-app (`lib/utils/web_view/web_view_desktop.dart`,
`lib/widgets/web_view_navigation_bar.dart`): remove `runWebViewNavigationBar`
and the navigation bar widget. The bot window gets the default toolbar with no
runner change. A Mixin-styled toolbar is a composer in each runner.

The built-in Flutter toolbar is removed, not moved. A `WebviewTitleBarBuilder`
cannot be carried over by changing its entry point. An application can still
render Flutter UI in a browser window from `compose`, but then it owns creating
the Flutter view, choosing the engine, and any communication across engines or
isolates. On Linux X11 that remains subject to flutter/flutter#186577.

## Validation

- Package tests: `create` forwards `composerArguments` and `showToolbar`;
  removed APIs are gone; creation needs no host.
- Example: the runners install a composer that handles
  `composerArguments == "sidebar"` with a horizontal layout (vertical button
  column left of the WebView) and returns `DWW_COMPOSE_DEFAULT` for everything
  else. A `composerArguments == "close:<callback>"` mode requests close from the
  named callback, for the close scenarios below.
- Integration scenarios in the existing `example/integration_test/app_test.dart`
  suite, on each platform:
  - Layout: default geometry, sidebar geometry, resize keeps the WebView in its
    slot.
  - Mixed ownership: default and sidebar windows open together; resize both and
    check the default toolbar stays visible; navigate both and check the
    application composer receives callbacks only for the sidebar window; close
    both and check each owner receives exactly one `closing`.
  - Close from each callback (`compose`, `navigation_changed`, `layout` on
    Windows, `closing`): no crash, no callback after `closing`, exactly one
    `closing`, `onClose` completes. For `compose`: no initial
    `navigation_changed`, window never shown, `create()` returns a closed
    `Webview`.
  - Default toolbar buttons drive navigation; `navigation_changed` order;
    `closing` before `onClose`; twenty close/recreate rounds.
- Windows and Linux runs go through `flutter-remote-test`; Linux on X11
  specifically, since that is the motivating crash. Native lifecycle checks do
  not prove physical keyboard/pointer delivery or visual quality, which need a
  manual pass on each platform.

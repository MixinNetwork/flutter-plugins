# Shared toolbar engine ownership test

Run on a POSIX host with a C++17 compiler and a Flutter source checkout:

```sh
./run_shared_toolbar_engine_test.sh /path/to/flutter
```

Verified against Flutter 3.47.6. This compiles the production toolbar engine and
message relay with Flutter's real public headers, client wrappers, internal
borrowed-controller declaration, and standard method codec. Only Win32 and the
Flutter C embedder functions are mocked. No package dependencies are downloaded.

Coverage:

- The engine is lazy, starts once, and registers its event relay once
- Missing internal borrowed-controller API produces an actionable error
- Implicit view 0 stays hidden and outlives every browser toolbar
- Browser IDs route independently of engine-assigned Flutter view IDs
- Snapshots contain per-view padding and withdraw records before native removal
- Closing the first or last browser leaves the engine alive
- A failed new controller leaves existing views intact
- Reopening uses the existing engine; plugin-owner teardown destroys it once

This is not a Windows build or a WebView2 integration test. Before release, run
the example on Windows with the target Flutter version and WebView2 installed:

1. Open at least three windows and interact with their independent toolbars
2. Close the first-created window, then another, and verify the survivor works
3. Close all windows and reopen several; verify one extra toolbar engine only
4. Close a window immediately while WebView2 is initializing, then repeat
5. Close during a pending URL-decision callback and verify no late navigation
6. Exercise `clearAll`, minimize/restore, move across DPI displays, resize only
   vertically, and open maximized
7. Omit the `runWebViewTitleBarWidget` entrypoint hook, then separately test
   non-positive `titleBarHeight`; verify no toolbar engine/view is started and the WebView occupies the full client area
8. Run both debug and release builds and check clean application shutdown

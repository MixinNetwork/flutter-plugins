# Linux shared titlebar engine investigation

> Historical design and validation notes. The shared Flutter titlebar implementation
> described here has been replaced by native composers. For the current design,
> see [Native window composer](native_window_composer.md) and the
> [package README](../README.md).

Research date: 2026-10-13. This note separates source facts from experiments and
does not establish Linux runtime acceptance.

## Current single-engine implementation

The main application and every Linux titlebar now use the application's existing
engine. `TitleBarViews` borrows that engine and adds explicit views through
`fl_view_new_for_engine`. No dedicated engine, hidden bootstrap window,
startup-argument dispatch, native message relay, or per-window fallback remains.
The Dart multi-view root contains both the main application and titlebars.

The source analysis and runtime evidence below describe the earlier dedicated
shared-titlebar implementation. They remain evidence of renderer behavior, not
acceptance results for the new single-engine code. Current ownership and checks
are documented in [the design note](shared_titlebar_engine.md).

## Related Flutter issues

- [#186577](https://github.com/flutter/flutter/issues/186577): the official
  multi-window example reproduces X11 `GLX BadAccess`, error 10 / minor 26, with
  reports that Wayland works. The reported trigger is window creation rather
  than this plugin's earlier rapid close/recreate sequence; identical symptoms
  do not prove an identical root cause.
- [#169470](https://github.com/flutter/flutter/issues/169470): earlier X11 startup
  failures also report GLX BadAccess, but involve ordinary single-window apps.
- [#192137](https://github.com/flutter/flutter/pull/192137): related engine work
  avoids clearing a drawing context before GTK finishes a frame. It targets
  another failure path and is not established as a fix for this reproduction.

## Verified SDK and API facts

The inspected local SDK reports Flutter 3.47.7, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`, Dart 3.13.5. The source checkout is at
that framework commit and has no local changes. Links below pin that revision.

- `fl_view_new(project)` creates the implicit view with ID 0. Its renderer's
  realization callback starts the engine. Secondary-view realization does not
  start an engine. The earlier dedicated-engine implementation used a private bootstrap window.
  The single-engine implementation no longer needs that window. See
  [fl_view.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_view.cc)
  (`realize_cb`, `fl_view_new`, `fl_view_new_for_engine`) and
  [the current view registry](../linux/title_bar_views.cc).
- `fl_view_new_for_engine` is in the public Linux header. It adds an explicit
  view to an existing non-headless engine. The public engine header does not
  expose `fl_engine_start`. There is no reason to copy private engine structures
  or register a second plugin instance for every titlebar. See
  [fl_view.h](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/public/flutter_linux/fl_view.h)
  and
  [fl_engine.h](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/public/flutter_linux/fl_engine.h).
- Flutter rendering uses an engine-owned EGL manager. Each view separately owns
  a GDK OpenGL context and compositor. On Wayland the compositor shares images;
  on X11/GLX it copies frame pixels through CPU memory. An EGL-based engine does
  not mean that its GTK presentation path is also EGL on X11. See
  [fl_opengl_manager.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_opengl_manager.cc)
  and
  [fl_view_renderer.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_view_renderer.cc)
  (`setup_opengl`).
- The compositor lifetime fix in
  [Flutter #188702](https://github.com/flutter/flutter/pull/188702) is already
  present. `gtk_widget_destroy` can force disposal while another thread retains
  a reference. The renderer therefore releases its compositor in `finalize`,
  after the last reference is dropped. This fixes the documented compositor
  use-after-free; it does not prove all context handling is correct.
- A local `git diff` between the previous reference framework
  `5fc346839b5d0eef006ed8404392afb4dfae428d` and 3.47.7 is empty for the entire
  `engine/src/flutter/shell/platform/linux` subtree. An SDK patch-version change
  alone is not a source-based explanation for different results.

## Source-supported context hypothesis

The following is a candidate cause to test, not a proven explanation of the
historical GLX failures:

1. Creating a view compositor creates its shader. `setup_shader` binds the
   engine's EGL **platform** context with
   `fl_opengl_manager_make_platform_current`.
2. Shader setup returns without clearing or restoring the prior current context.
   Shader disposal also binds that EGL platform context and returns without
   clearing or restoring it.
3. GTK view drawing binds a GDK context with `gdk_gl_context_make_current` and
   clears it afterward. On X11 this crosses between EGL engine work and GLX
   presentation work on the platform thread.
4. Therefore a lifecycle operation can leave a directly-bound EGL context
   current when subsequent GTK/GLX work starts. Test whether explicitly clearing
   the EGL binding at that boundary removes the observed failure.

The relevant functions are `setup_shader` and
`fl_compositor_opengl_shader_dispose` in
[fl_compositor_opengl_shader.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_compositor_opengl_shader.cc),
`fl_opengl_manager_make_platform_current` in
[fl_opengl_manager.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_opengl_manager.cc),
and `fl_view_renderer_draw` in
[fl_view_renderer.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_view_renderer.cc).

An isolated native probe can log `eglGetCurrentDisplay`,
`eglGetCurrentContext`, and `gdk_gl_context_get_current` around realization,
destruction, and recreation. Compare the unchanged baseline with a variant that
clears the current EGL binding using `eglMakeCurrent(display, EGL_NO_SURFACE,
EGL_NO_SURFACE, EGL_NO_CONTEXT)` at those boundaries. Record the EGL result and
error, and run on the GTK platform thread. Calling only GTK's context-clear API
does not demonstrate that a context bound directly by EGL was cleared.

Do not clear bindings from unrelated threads, globally inject this behavior into
every GTK widget, or promote a successful short probe into a general engine fix.
A plugin workaround needs a reproducible failure before the change and repeated
success after it, with titlebar rendering, WebKit rendering, focus, and cleanup
still working.

GTK also caches its current context in thread-local storage.
`gdk_gl_context_make_current` returns early when its cached pointer already
matches the requested context. Direct EGL calls do not update that cache. A
probe should therefore compare the actual EGL/GLX bindings with GTK's cached
context, and test clearing EGL first and then GTK's current-context state. See
[GTK 3.24.33 gdkglcontext.c](https://github.com/GNOME/gtk/blob/3.24.33/gdk/gdkglcontext.c)
(`gdk_gl_context_make_current`, `gdk_gl_context_clear_current`). This is another
source-supported conflict mechanism, not a confirmed runtime diagnosis.

There is an important limit to a plugin-side realization hook. Flutter's
`setup_opengl` creates and realizes its GDK context and then immediately creates
the compositor/shader in the same function. A callback after `FlView` realization
cannot insert cleanup between those internal operations. If shader setup already
fails during first realization, clearing bindings afterward may prevent a later
crash while leaving incomplete initialization. Such a result is not migration
acceptance. A remaining internal transition failure may require an upstream
embedding fix rather than more plugin lifecycle machinery.

`GDK_GL=gles` must not be described as forcing EGL on GTK3 X11. The inspected
[GTK 3.24.33 X11 context implementation](https://github.com/GNOME/gtk/blob/3.24.33/gdk/x11/gdkglcontext-x11.c)
uses GLX. Selecting the GLES API/profile does not establish a different native
context transport. Match the installed GTK version before relying on its exact
behavior. Native Wayland can be evaluated as a separate supported migration
scope while X11 retains the existing path; a Wayland pass does not remove the
X11 restriction.

## Why view removal and references need care

The plugin's `RemoveView` removes its Dart routing descriptor. Actual engine
view removal occurs inside `FlView::dispose`. The engine removes the renderable
from its lookup immediately, then calls asynchronous embedder `RemoveView`.
Presentation obtains a strong reference from a protected weak-reference lookup.
Thus removal stops future lookups but does not retroactively cancel a present
already in progress. See
[fl_engine.cc](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/linux/fl_engine.cc)
(`get_renderable`, `compositor_present_view_callback`, `fl_engine_remove_view`)
and [the plugin cleanup](../linux/webview_window.cc).

Retaining another `g_object_ref` does not prevent forced widget disposal. GTK
explicitly documents that a destroyed widget must no longer be queried as an
ordinary widget. See [GtkWidget.destroy](https://docs.gtk.org/gtk3/method.Widget.destroy.html).
An idle delay or extra reference is therefore not a demonstrated renderer fix.
The public `FlView` API also provides no view-removal completion callback for
plugins. Reaching into the private engine API to add one increases compatibility
cost without yet explaining the GLX problem.

## Historical migration acceptance

The migration preserves the existing shared host and removes the unused legacy
engine branch and experimental flag. Keep the no-hook and zero-height paths
engine-free. Do not change release metadata for this work. Migration completion
and renderer acceptance are separate results.

Validate unchanged and candidate builds from the same source snapshot and SDK:

- X11/GLX, native Wayland, and software rendering as separate results.
- Three simultaneous titlebars sharing one engine, with distinct native view
  and browser IDs and isolated navigation commands.
- Close first/middle/last, close all and reopen, immediate close, duplicate close,
  and application shutdown while views are alive; repeat at least 20 rounds.
- Real titlebar painting and keyboard/pointer focus transfers to and from WebKit.
- Debug and Release, retained view/context counts, and sustained memory use.

A WSLg pass establishes that environment only. A software pass is diagnostic
evidence and cannot establish GLX safety. Remote execution records belong in the
main task's validation report; this note records no unexecuted scenario as a pass.

## Historical dedicated-engine runtime evidence

Code snapshot: `20261013T065613-9d96cae225bd`, SHA-256
`9d96cae225bd135d499bba5801af7493f419b38bca7dc9d266ff0e23dfcf20ba`.
WSL Ubuntu 22.04, GTK 3.24.33, WebKitGTK 2.50.4, Flutter 3.47.7 / Dart 3.13.5.
Windows doctor reported the same Flutter/Dart versions; no Windows runtime
regression was executed for this Linux migration.

- Package analysis and eleven WSL tests passed (exit 0).
- The final shared smoke target built successfully in Debug (exit 0).
- X11 reproduced shader context warnings and `GLX BadAccess`, request 149,
  minor 26. The process exited on SIGTRAP (Python return code -5), after the
  second close/recreate cycle. It did not pass lifecycle acceptance.
- Native Wayland completed all twenty cycles, including duplicate close,
  zero-height toolbar, immediate close, surviving browser navigation and
  reopening after all browsers closed. The runner terminated its process group
  after the PASS marker; this is not evidence of natural application shutdown.
- Engine pointers remained shared while explicit view IDs differed. First-frame
  callbacks were observed; this does not assert visual correctness or real
  keyboard/pointer delivery.

An earlier diagnostic snapshot, `20261013T065250-fa8c10723658`, explicitly
cleared GDK/EGL bindings around creation, realization and destruction. X11
still failed with the same GLX error. That workaround and its extra dependency
were removed. This rejects that boundary-only workaround, not every possible
context-handling explanation.

The same diagnostic snapshot was also run with
`FLUTTER_LINUX_RENDERER=software`. Both engines selected software, then Flutter
aborted on `Impeller DlText cannot be drawn to a Skia canvas` (SIGABRT, -6).
Passing `--enable-software-rendering` directly to the example executable had
previously left the OpenGL renderer active and is not a valid software control.
Neither diagnostic is retained as a rendering mode in the plugin.

Reproduce from `example`:

```sh
GDK_BACKEND=x11 flutter run -d linux -t lib/shared_engine_smoke.dart --dart-define=SMOKE_AUTORUN=true
GDK_BACKEND=wayland flutter run -d linux -t lib/shared_engine_smoke.dart --dart-define=SMOKE_AUTORUN=true
```

Local logs are under
`~/.codex/remote-flutter-tests/20261013T065613-9d96cae225bd/`, including
`linux-shared-probe.log` and the unit-test result JSON/log. Renderer diagnostic
logs remain under the earlier snapshot directory. These directories are local
validation artifacts, not repository inputs. Documentation was completed after
the tested code snapshot; no runtime source changed afterward.

Still unverified: Release, physical Linux desktop GPU/driver combinations,
visual/input/focus behavior, accessibility, sustained memory use, and native
shutdown with open browser windows. The migration does not resolve these by
maintaining a legacy engine implementation.

## Single-engine runtime evidence

On `20261013T100032-31e3c3fc9284`, the application and titlebars used one engine.
Nine WSL package tests and Debug compilation passed. Wayland completed all
20 lifecycle rounds and exited 0. X11 still reproduced GLX BadAccess (minor 26)
and exited on SIGTRAP (-5). Logs are in `single-engine-linux-smoke.log` with
individual exit codes in `single-engine-linux-smoke.json` under that run's local
artifact directory. These are single-engine results; the older dedicated-engine
results above are historical only. No upstream comparison program was run.

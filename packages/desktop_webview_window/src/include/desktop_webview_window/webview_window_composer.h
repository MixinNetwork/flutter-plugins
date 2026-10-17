// Native window composition for desktop_webview_window.
//
// The plugin owns each browser's top-level window and WebView. A composer
// decides what else the window contains and where the WebView sits. Install
// one from the runner before the first browser is created; without one, the
// plugin's default composer adds a native toolbar above the WebView.
//
// Concrete types of DWWComposeRequest::window / webview_view:
//   macOS:   NSWindow*  / NSView*    (not yet in the window's hierarchy)
//   Linux:   GtkWindow* / GtkWidget* (not yet parented)
//   Windows: HWND       / HWND       (hidden child of the window)
//
// All callbacks and functions run on the platform main thread. Pointers are
// borrowed and must not be used after closing(). Do not destroy the window or
// webview_view, replace the window's delegate or window procedure, or move
// webview_view into another window.

#ifndef DESKTOP_WEBVIEW_WINDOW_WEBVIEW_WINDOW_COMPOSER_H_
#define DESKTOP_WEBVIEW_WINDOW_WEBVIEW_WINDOW_COMPOSER_H_

#include <stdint.h>

#if defined(_WIN32)
#ifdef FLUTTER_PLUGIN_IMPL
#define DWW_COMPOSER_API __declspec(dllexport)
#else
#define DWW_COMPOSER_API __declspec(dllimport)
#endif
#else
#define DWW_COMPOSER_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int64_t browser;        // Same value as Webview.id in Dart.
  void* window;           // Borrowed top-level window.
  void* webview_view;     // Borrowed WebView container view.
  const char* arguments;  // CreateConfiguration.composerArguments, or NULL.
  int32_t show_toolbar;   // CreateConfiguration.showToolbar.
} DWWComposeRequest;

typedef struct {
  int64_t browser;
  int32_t can_go_back;
  int32_t can_go_forward;
  int32_t is_loading;
  const char* url;    // Borrowed for the duration of the call, or NULL.
  const char* title;  // Borrowed for the duration of the call, or NULL.
} DWWNavigationState;

typedef enum {
  // The default composer owns this window. The application composer must not
  // have touched the window or webview_view, and receives no further
  // callbacks for this browser.
  DWW_COMPOSE_DEFAULT = 0,
  // The application composer owns this window and receives all its callbacks.
  DWW_COMPOSE_HANDLED = 1,
} DWWComposeResult;

typedef struct {
  void* user;
  // Required. Called once per browser, before the window is first shown. If
  // it handles the window without placing webview_view, the WebView fills the
  // window.
  DWWComposeResult (*compose)(void* user, const DWWComposeRequest* request);
  // Optional. Called on every navigation state change after compose.
  void (*navigation_changed)(void* user, const DWWNavigationState* state);
  // Optional. Windows only: the client area changed, in physical pixels. Use
  // GetDpiForWindow(window) for the scale. Without it, webview_view fills the
  // client area.
  void (*layout)(void* user, int64_t browser, int32_t width, int32_t height);
  // Optional. Called exactly once before the window and its views are
  // destroyed. No other callback for this browser follows it.
  void (*closing)(void* user, int64_t browser);
} DWWComposer;

// Copies |composer|. NULL restores the default composer. Affects browsers
// created afterwards.
DWW_COMPOSER_API void dww_set_composer(const DWWComposer* composer);

// Browser control. Each returns zero when the browser is unknown, closing or
// closed. A close requested from inside a composer callback takes effect after
// that callback returns.
DWW_COMPOSER_API int32_t dww_browser_go_back(int64_t browser);
DWW_COMPOSER_API int32_t dww_browser_go_forward(int64_t browser);
DWW_COMPOSER_API int32_t dww_browser_reload(int64_t browser);
DWW_COMPOSER_API int32_t dww_browser_stop(int64_t browser);
DWW_COMPOSER_API int32_t dww_browser_close(int64_t browser);

#ifdef __cplusplus
}
#endif

#endif  // DESKTOP_WEBVIEW_WINDOW_WEBVIEW_WINDOW_COMPOSER_H_

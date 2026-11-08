// C adapter between the Swift plugin and the shared C++ composer runtime.
// Internal to the plugin; applications use webview_window_composer.h.

#ifndef DESKTOP_WEBVIEW_WINDOW_DWW_DARWIN_H_
#define DESKTOP_WEBVIEW_WINDOW_DWW_DARWIN_H_

#include "webview_window_composer.h"

#ifdef __cplusplus
extern "C" {
#endif

// Browser control implemented by the Swift window controller. Each returns
// zero when the browser is closing or closed.
typedef struct {
  void* target;
  int32_t (*go_back)(void* target);
  int32_t (*go_forward)(void* target);
  int32_t (*reload)(void* target);
  int32_t (*stop)(void* target);
  int32_t (*close)(void* target);
} DWWDarwinBrowser;

int64_t dww_darwin_next_browser_id(void);
void dww_darwin_register_browser(int64_t browser, const DWWDarwinBrowser* ops);
void dww_darwin_unregister_browser(int64_t browser);

// The Swift default composer, installed once by the plugin.
void dww_darwin_set_default_composer(const DWWComposer* composer);

// One browser's ComposerBinding.
typedef struct DWWDarwinBinding DWWDarwinBinding;
DWWDarwinBinding* dww_darwin_binding_new(void);
void dww_darwin_binding_free(DWWDarwinBinding* binding);
void dww_darwin_binding_compose(DWWDarwinBinding* binding,
                                const DWWComposeRequest* request);
void dww_darwin_binding_navigation_changed(DWWDarwinBinding* binding,
                                           const DWWNavigationState* state);
void dww_darwin_binding_closing(DWWDarwinBinding* binding, int64_t browser);
void dww_darwin_binding_begin_close(DWWDarwinBinding* binding);
int32_t dww_darwin_binding_dispatching(const DWWDarwinBinding* binding);

#ifdef __cplusplus
}
#endif

#endif  // DESKTOP_WEBVIEW_WINDOW_DWW_DARWIN_H_

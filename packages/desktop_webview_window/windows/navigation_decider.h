// Synchronous navigation decisions from Dart.
//
// WebView2's NavigationStarting has no deferral, so the decision must be made
// before the handler returns. Dart registers a listener once per isolate. When
// the UI and platform threads are merged, the listener is called directly;
// otherwise the request is posted to the isolate and the platform thread blocks
// until Dart replies or a timeout allows the navigation.

#ifndef DESKTOP_WEBVIEW_WINDOW_NAVIGATION_DECIDER_H_
#define DESKTOP_WEBVIEW_WINDOW_NAVIGATION_DECIDER_H_

#include <cstdint>
#include <string>

namespace dww {

// Returns false when Dart declines |url|. Allows the navigation when no
// listener is registered, the isolate is gone or Dart does not reply in time.
bool DecideNavigation(int64_t browser, const std::string& url);

}  // namespace dww

extern "C" {

// Returns nonzero to allow the navigation. |url| is UTF-8 without a NUL.
typedef int32_t (*DWWNavigationDecide)(int64_t browser, const uint8_t* url,
                                       int32_t length);

// Replaces any previous listener and returns its generation, or 0 on failure.
// |merged| is nonzero when Dart runs on the platform thread.
__declspec(dllexport) int64_t dww_navigation_register(void* api, int64_t port,
                                                      DWWNavigationDecide decide,
                                                      int32_t merged);
// Answers a request posted to the port. Returns 0 when it is no longer waiting.
__declspec(dllexport) int32_t dww_navigation_complete(int64_t generation,
                                                      int64_t request,
                                                      int32_t allow);
__declspec(dllexport) void dww_navigation_unregister(int64_t generation);
}

#endif  // DESKTOP_WEBVIEW_WINDOW_NAVIGATION_DECIDER_H_

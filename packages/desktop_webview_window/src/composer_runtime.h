// Platform-independent composer dispatch shared by every platform.

#ifndef DESKTOP_WEBVIEW_WINDOW_COMPOSER_RUNTIME_H_
#define DESKTOP_WEBVIEW_WINDOW_COMPOSER_RUNTIME_H_

#include <string>

#include "include/desktop_webview_window/webview_window_composer.h"

namespace dww {

// Implemented by each platform's browser window. Each method returns false
// when the browser is closing or closed.
class Browser {
 public:
  virtual ~Browser() = default;
  virtual bool GoBack() = 0;
  virtual bool GoForward() = 0;
  virtual bool Reload() = 0;
  virtual bool Stop() = 0;
  virtual bool Close() = 0;
};

int64_t NextBrowserId();

// Makes |browser| reachable through the dww_browser_* functions.
void RegisterBrowser(int64_t id, Browser* browser);
void UnregisterBrowser(int64_t id);

// The platform's built-in composer.
const DWWComposer& DefaultComposer();

// The host of an absolute URL, such as "example.com"; empty when it has none.
std::string HostOf(const char* url);

// One browser's composer: the window's owner, callback gating after close, and
// whether a callback is on the stack.
class ComposerBinding {
 public:
  // Snapshots the installed application composer.
  ComposerBinding();

  // Decides the window's owner for its lifetime.
  void Compose(const DWWComposeRequest& request);
  void NavigationChanged(const DWWNavigationState& state);
  // Returns false when the owner has no layout callback.
  bool Layout(int64_t browser, int32_t width, int32_t height);
  // Delivers closing once. Later navigation and layout are dropped.
  void Closing(int64_t browser);

  // Drops navigation and layout from now on, before closing is delivered.
  void BeginClose() { closing_ = true; }
  // True while a composer callback for this browser is running.
  [[nodiscard]] bool dispatching() const { return depth_ > 0; }

 private:
  class Scope {
   public:
    explicit Scope(int& depth) : depth_(depth) { ++depth_; }
    ~Scope() { --depth_; }

   private:
    int& depth_;
  };

  DWWComposer app_{};
  DWWComposer owner_{};
  int depth_ = 0;
  bool closing_ = false;
  bool closed_ = false;
};

}  // namespace dww

#endif  // DESKTOP_WEBVIEW_WINDOW_COMPOSER_RUNTIME_H_

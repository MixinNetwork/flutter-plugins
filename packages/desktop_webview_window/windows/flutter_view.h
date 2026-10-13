#ifndef WEBVIEW_WINDOW_WINDOWS_FLUTTER_VIEW_H_
#define WEBVIEW_WINDOW_WINDOWS_FLUTTER_VIEW_H_

#include <windows.h>
#include <flutter_windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <optional>
#include <string>

namespace webview_window {

class SharedToolbarEngine;

// Owns only a view controller. The plugin's SharedToolbarEngine owns its engine.
class FlutterView {
 public:
  ~FlutterView();
  FlutterView(const FlutterView&) = delete;
  FlutterView& operator=(const FlutterView&) = delete;

  std::optional<LRESULT> HandleTopLevelWindowProc(HWND hwnd, UINT message,
                                                 WPARAM w_param, LPARAM l_param);
  [[nodiscard]] HWND GetWindow() const;
  [[nodiscard]] int64_t GetViewId() const { return view_id_; }
  void ReloadSystemFonts();
  void ForceRedraw();

 private:
  friend class SharedToolbarEngine;
  FlutterView(SharedToolbarEngine* owner,
              FlutterDesktopViewControllerRef controller, int64_t view_id);

  SharedToolbarEngine* owner_;
  FlutterDesktopViewControllerRef controller_;
  int64_t view_id_;
};

// One lazy, dedicated engine per plugin owner, retained even with no open views.
// Every controller borrows this engine; none may use the owning create API.
class SharedToolbarEngine {
 public:
  SharedToolbarEngine() = default;
  ~SharedToolbarEngine();
  SharedToolbarEngine(const SharedToolbarEngine&) = delete;
  SharedToolbarEngine& operator=(const SharedToolbarEngine&) = delete;

  std::unique_ptr<FlutterView> CreateView(int64_t web_view_id, int top_padding,
                                        int width, int height, std::string* error);
  void RemoveView(int64_t view_id);
  void ReloadSystemFonts();

 private:
  bool Initialize(std::string* error);
  void NotifyViewsChanged();
  flutter::EncodableList GetViews() const;

  FlutterDesktopEngineRef engine_ = nullptr;
  // Windows reserves view 0 for the engine's entire lifetime. Keep it hidden;
  // every browser toolbar must use an independently removable explicit view.
  FlutterDesktopViewControllerRef implicit_controller_ = nullptr;
  // Flutter's installed headers omit this in-progress API. Its ABI is isolated
  // in flutter_view.cc and resolved from the loaded stock engine at runtime.
  FARPROC create_view_controller_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<int64_t, flutter::EncodableMap> views_;
};

}  // namespace webview_window

#endif  // WEBVIEW_WINDOW_WINDOWS_FLUTTER_VIEW_H_

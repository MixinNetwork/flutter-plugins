//
// Created by yangbin on 2021/11/12.
//

#ifndef WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_H_
#define WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_H_

#include <windows.h>

#include <string>
#include <functional>
#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>

#include "wil/resource.h"
#include "wil/com.h"

#include "WebView2.h"

namespace webview_window {

class WebView : public std::enable_shared_from_this<WebView> {

 public:

  // Posts a browser event to Dart; |args| gains the browser "id".
  using EventSink =
      std::function<void(const std::string& method, flutter::EncodableMap args)>;
  // Asks Dart to decide a top-level navigation before it starts. Returns false
  // to cancel it.
  using NavigationRequest = std::function<bool(const std::wstring& url)>;

  struct NavigationState {
    bool can_go_back = false;
    bool can_go_forward = false;
    bool is_loading = false;
    std::wstring url;
    std::wstring title;
    bool operator==(const NavigationState& other) const {
      return can_go_back == other.can_go_back &&
             can_go_forward == other.can_go_forward &&
             is_loading == other.is_loading && url == other.url &&
             title == other.title;
    }
  };

  // |state_changed| is called whenever State() may have changed.
  WebView(EventSink emit, NavigationRequest request_navigation,
          std::function<void()> state_changed, int64_t web_view_id,
          std::wstring userDataFolder, bool deny_camera_and_microphone,
          std::wstring javascript_bridge);

  virtual ~WebView();

  void Create(std::function<void(HRESULT)> callback);

  void Close();

  [[nodiscard]] const wil::unique_hwnd &NativeWindow() const { return view_window_; }

  void UpdateBounds();

  void Navigate(const std::wstring &url);

  void AddScriptToExecuteOnDocumentCreated(const std::wstring &javaScript);

  void SetApplicationNameForUserAgent(const std::wstring &application_name);

  void GoBack();

  void GoForward();

  void Reload();

  void Stop();

  void GetAllCookies(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer);

  void openDevToolsWindow();

  void ExecuteJavaScript(const std::wstring &javaScript,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer);

  // Delivers a bridge message to window.desktopWebview listeners.
  void PostJavaScriptMessage(const std::wstring &message,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer);

  // Returns keyboard focus to the page when its window is activated.
  void Focus();

  void setTriggerOnUrlRequestedEvent(const bool value);

  // Top-level navigations wait for Dart only while this is set.
  void SetUrlRequestEnabled(bool enabled) { url_request_enabled_ = enabled; }

  [[nodiscard]] NavigationState State() const;

  // Whether WebView2 renders. It does not follow its host window's
  // visibility, so a webview in a window created hidden stays blank when the
  // window is shown unless it is told.
  void SetVisible(bool visible);

 private:
  wil::unique_hwnd view_window_;

  // Pointer to WebViewController
  wil::com_ptr<ICoreWebView2Controller> webview_controller_;

  // Pointer to WebView
  wil::com_ptr<ICoreWebView2> webview_;

  wil::com_ptr<ICoreWebView2Environment> environment_;

  std::wstring default_user_agent_;

  EventSink emit_;

  NavigationRequest request_navigation_;

  std::function<void()> state_changed_;

  bool url_request_enabled_ = false;

  bool loading_ = false;

  void NotifyStateChanged();

  std::wstring javascript_bridge_;

  int64_t web_view_id_;

  std::function<void(HRESULT)> on_web_view_created_callback_;

  std::wstring user_data_folder_;

  bool triggerOnUrlRequestedEvent{true};

  bool deny_camera_and_microphone_{false};

  // Applied when the controller is created, if SetVisible came first.
  bool visible_{true};

  void Emit(const std::string& method, flutter::EncodableMap args = {});

  // The last declined top-level URL, without its fragment. WebView2 may start
  // the document request before a NavigationStarting cancel takes effect, so
  // WebResourceRequested answers that request locally.
  std::wstring declined_url_;

  bool closed_ = false;

  void CompleteCreation(HRESULT result);

  HRESULT OnWebviewControllerCreated();

  [[nodiscard]] bool CanGoBack() const;

  [[nodiscard]] bool CanGoForward() const;

};

}

#endif //WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_H_

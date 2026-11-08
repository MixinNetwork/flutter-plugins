//
// Created by yangbin on 2021/10/20.
//

#ifndef _WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_
#define _WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_

#include <Windows.h>

#include <flutter/encodable_value.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include <wrl.h>
#include "wil/com.h"
#include "WebView2.h"

#include "composer_runtime.h"
#include "web_view.h"

class WebviewWindow : public std::enable_shared_from_this<WebviewWindow>,
                      public dww::Browser {
 public:
  using EventSink = webview_window::WebView::EventSink;
  using NavigationRequest = webview_window::WebView::NavigationRequest;

  enum class CreateOutcome { kReady, kClosed, kFailed };
  using CreateCallback =
      std::function<void(CreateOutcome outcome, const std::string& error)>;

  struct Options {
    std::wstring title;
    int width = 1280;
    int height = 720;
    int x = 0;
    int y = 0;
    bool use_position = false;
    bool open_maximized = false;
    bool open_hidden = false;
    int brightness = -1;
    uint32_t title_bar = 0xF;
    bool deny_camera_and_microphone = false;
    std::wstring user_data_folder;
    std::wstring javascript_bridge;
    std::optional<std::string> composer_arguments;
  };

  WebviewWindow(EventSink emit, NavigationRequest request_navigation,
                int64_t window_id, std::function<void()> on_close_callback);

  ~WebviewWindow() override;

  // Creates the window, composes it and starts WebView2. |callback| runs once:
  // ready, closed (also when closed before WebView2 finished), or failed.
  void CreateAndShow(const Options& options, CreateCallback callback);

  // OS callback called by message pump.
  static LRESULT CALLBACK WndProc(HWND window,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam) noexcept;

  // Requests closing. Inside a composer callback it takes effect afterwards.
  bool Close() override;

  bool GoBack() override;

  bool GoForward() override;

  bool Reload() override;

  bool Stop() override;

  void SetBrightness(int brightness);

  [[nodiscard]] HWND GetHwnd() const { return hwnd_.get(); }

  [[nodiscard]] const std::shared_ptr<webview_window::WebView>& GetWebView() const {
    return web_view_;
  }

 private:
  // Retrieves a class instance pointer for |window|
  static WebviewWindow* GetThisFromHandle(HWND window) noexcept;

  EventSink emit_;

  NavigationRequest request_navigation_;

  wil::unique_hwnd hwnd_;

  int64_t window_id_;

  std::function<void()> on_close_callback_;

  std::shared_ptr<webview_window::WebView> web_view_;

  CreateCallback create_callback_;

  dww::ComposerBinding composer_;

  bool closing_ = false;

  bool destroyed_ = false;

  // Follow the system theme until Webview.setBrightness pins one, so the frame
  // and the default title bar agree.
  int brightness_ = -1;

  std::optional<webview_window::WebView::NavigationState> published_;

  void CompleteCreation(CreateOutcome outcome, const std::string& error = "");

  // Tears the window down now. Only valid outside composer callbacks.
  void DestroyNow();

  void OnClosed();

  void Layout();

  void PublishNavigationState();

  LRESULT MessageHandler(HWND window,
                         UINT message,
                         WPARAM wparam,
                         LPARAM lparam) noexcept;
};

#endif //_WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_

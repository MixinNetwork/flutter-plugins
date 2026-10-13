//
// Created by yangbin on 2021/10/20.
//

#include <windows.h>

#include "webview_window.h"

#include <tchar.h>
#include <algorithm>
#include <utility>

#include "strconv.h"
#include "utils.h"

#include "include/desktop_webview_window/desktop_webview_window_plugin.h"

namespace {

TCHAR kWebViewWindowClassName[] = _T("WebviewWindow");

using namespace webview_window;

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

}

using namespace Microsoft::WRL;

WebviewWindow::WebviewWindow(
    MethodChannelPtr method_channel,
    int64_t window_id,
    int title_bar_height,
    int title_bar_top_padding,
    webview_window::TitleBarViews* title_bar_views,
    std::function<void()> on_close_callback
) : method_channel_(std::move(method_channel)),
    hwnd_(),
    window_id_(window_id),
    on_close_callback_(std::move(on_close_callback)),
    title_bar_views_(title_bar_views),
    title_bar_top_padding_(title_bar_top_padding),
    title_bar_height_(title_bar_height) {

}

WebviewWindow::~WebviewWindow() {
  // No callbacks may reenter a partially destructed window.
  if (hwnd_) {
    SetWindowLongPtr(hwnd_.get(), GWLP_USERDATA, 0);
  }
  flutter_action_bar_.reset();
  if (web_view_) {
    web_view_->Close();
    web_view_.reset();
  }
  hwnd_.reset();
}

void WebviewWindow::CreateAndShow(const std::wstring &title, int height, int width,
                                  const std::wstring &userDataFolder,
                                  int windowPosX, int windowPosY, bool useWindowPositionAndSize,
                                  bool openMaximized, bool openHidden,
                                  bool denyCameraAndMicrophone, bool showSystemTitleBar,
                                  CreateCallback callback) {

  // Keep this alive through synchronous failure callbacks and window messages.
  auto keep_alive = shared_from_this();
  create_callback_ = std::move(callback);
  RegisterWindowClass(kWebViewWindowClassName, WebviewWindow::WndProc);

  const POINT target_point = {static_cast<LONG>(10), static_cast<LONG>(10)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  const double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  DWORD style = showSystemTitleBar ? WS_OVERLAPPEDWINDOW :
      WS_POPUP | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
  if (openMaximized) {
    style |= WS_MAXIMIZE;
  }
  hwnd_ = wil::unique_hwnd(::CreateWindow(
      kWebViewWindowClassName, title.c_str(), style,
      useWindowPositionAndSize ? windowPosX : CW_USEDEFAULT,
      useWindowPositionAndSize ? windowPosY : CW_USEDEFAULT,
      useWindowPositionAndSize ? width : Scale(width, scale_factor),
      useWindowPositionAndSize ? height : Scale(height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this));
  if (!hwnd_) {
    CompleteCreation(false, "Failed to create the browser window.");
    OnClosed();
    return;
  }
  if (!useWindowPositionAndSize && !openMaximized) {
    ClipOrCenterWindowToMonitor(hwnd_.get(), MONITOR_CENTER);
  }

  RECT bounds;
  GetClientRect(hwnd_.get(), &bounds);
  const int title_bar_height = Scale(title_bar_height_, scale_factor);
  if (title_bar_height_ > 0) {
    std::string error;
    flutter_action_bar_ = title_bar_views_->CreateView(
        window_id_, title_bar_top_padding_, bounds.right - bounds.left,
        title_bar_height, &error);
    if (!flutter_action_bar_) {
      CompleteCreation(false, error);
      Close();
      return;
    }
    if (destroyed_) {
      flutter_action_bar_.reset();
      return;
    }
    SetParent(flutter_action_bar_->GetWindow(), hwnd_.get());
    ShowWindow(flutter_action_bar_->GetWindow(), SW_SHOW);
  }

  web_view_ = std::make_shared<webview_window::WebView>(
      method_channel_, window_id_, userDataFolder, denyCameraAndMicrophone);
  web_view_->SetVisible(!openHidden);
  SetParent(web_view_->NativeWindow().get(), hwnd_.get());
  ResizeChildren(hwnd_.get());
  ShowWindow(web_view_->NativeWindow().get(), SW_SHOW);
  if (!openHidden) {
    ShowWindow(hwnd_.get(), openMaximized ? SW_SHOWMAXIMIZED : SW_SHOW);
    UpdateWindow(hwnd_.get());
  }

  // Start asynchronous WebView2 initialization only after ownership, parenting,
  // and toolbar routing have been installed. Closing now cancels this reply.
  if (destroyed_ || !web_view_) {
    return;
  }
  web_view_->Create([weak = weak_from_this()](HRESULT result) {
    auto window = weak.lock();
    if (!window || window->destroyed_) {
      return;
    }
    if (SUCCEEDED(result)) {
      window->CompleteCreation(true);
    } else {
      window->CompleteCreation(false, "Failed to initialize the browser view.");
      window->Close();
    }
  });
}

void WebviewWindow::CompleteCreation(bool success, const std::string& error) {
  auto callback = std::exchange(create_callback_, nullptr);
  if (callback) {
    callback(success, error);
  }
}

void WebviewWindow::Close() {
  auto keep_alive = shared_from_this();
  if (hwnd_) {
    DestroyWindow(hwnd_.get());
  } else {
    OnClosed();
  }
}

void WebviewWindow::OnClosed() {
  if (destroyed_) {
    return;
  }
  destroyed_ = true;
  flutter_action_bar_.reset();
  if (web_view_) {
    web_view_->Close();
    web_view_.reset();
  }
  CompleteCreation(false, "Browser window closed before initialization completed.");
  method_channel_->InvokeMethod(
      "onWindowClose", std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("id"), flutter::EncodableValue(window_id_)}}));
  auto callback = std::exchange(on_close_callback_, nullptr);
  if (callback) {
    callback();
  }
}

void WebviewWindow::ResizeChildren(HWND window) {
  RECT bounds;
  GetClientRect(window, &bounds);
  const auto monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  const int toolbar_height = flutter_action_bar_ ? Scale(title_bar_height_, scale) : 0;
  if (web_view_ && web_view_->NativeWindow()) {
    MoveWindow(web_view_->NativeWindow().get(), 0, toolbar_height, width,
               (std::max)(0, height - toolbar_height), true);
    if (web_view_) {
      web_view_->UpdateBounds();
    }
  }
  if (flutter_action_bar_) {
    MoveWindow(flutter_action_bar_->GetWindow(), 0, 0, width, toolbar_height, true);
    if (flutter_action_bar_) {
      flutter_action_bar_->ForceRedraw();
    }
  }
}

void WebviewWindow::SetBrightness(int brightness) {
}

void WebviewWindow::setVisibility(bool visible)
{
  if(visible)
    ::ShowWindow(hwnd_.get(), SW_SHOW);
  else
    ::ShowWindow(hwnd_.get(), SW_HIDE);
  if (web_view_) {
    web_view_->SetVisible(visible);
  }
}

void WebviewWindow::moveWebviewWindow(int left, int top, int width, int height) {
  ::SetWindowPos(hwnd_.get(), nullptr, left, top, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}

void WebviewWindow::bringToForeground(bool maximized) {
  SetForegroundWindow(hwnd_.get());
  if (maximized) {
    if (web_view_) {
      web_view_->SetVisible(true);
    }
    ::ShowWindow(hwnd_.get(), SW_MAXIMIZE);
  }
}

void WebviewWindow::getPositionalParameters(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer) {
  RECT rc;
  GetWindowRect(hwnd_.get(), &rc);

  std::unique_ptr<WINDOWPLACEMENT> wp(new WINDOWPLACEMENT{});
  wp->length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd_.get(), wp.get());
  std::map<flutter::EncodableValue, flutter::EncodableValue> m{
    {"left", rc.left},
    {"top", rc.top},
    {"width", rc.right-rc.left},
    {"height", rc.bottom-rc.top},
    {"maximized", wp->showCmd==SW_MAXIMIZE}};
  completer->Success(flutter::EncodableValue(m));
}

// static
LRESULT CALLBACK
WebviewWindow::WndProc(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam
) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT *>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

//    auto that = static_cast<WebviewWindow *>(window_struct->lpCreateParams);
//    that->hwnd_ = window;
  } else if (WebviewWindow *that = GetThisFromHandle(window)) {
    // Closing erases the plugin map. Keep the object alive until WndProc returns.
    auto keep_alive = that->weak_from_this().lock();
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
WebviewWindow::MessageHandler(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam
) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_action_bar_ && message != WM_DESTROY) {
    std::optional<LRESULT> result = flutter_action_bar_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_DESTROY: {
      // The OS is already destroying this HWND; do not destroy it a second time
      // when the final shared owner is released at the end of WndProc.
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      hwnd_.release();
      OnClosed();
      return 0;
    }
    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT *>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE: {
      ResizeChildren(hwnd);
      return 0;
    }
    case WM_FONTCHANGE: {
      if (flutter_action_bar_) {
        flutter_action_bar_->ReloadSystemFonts();
      }
      break;
    }
    case WM_ACTIVATE: {
      return 0;
    }
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

// static
WebviewWindow *WebviewWindow::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<WebviewWindow *>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}


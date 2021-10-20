//
// Created by yangbin on 2021/10/20.
//

#include <windows.h>

#include "webview_window.h"
#include <tchar.h>

#include <utility>
#include "strconv.h"

#include "flutter/encodable_value.h"
#include <flutter_windows.h>

namespace {

TCHAR kWindowClassName[] = _T("WebviewWindow");

bool class_registered_;

const wchar_t *GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, IDI_APPLICATION);
    window_class.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = WebviewWindow::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

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
    std::function<void()> on_close_callback
) : method_channel_(std::move(method_channel)),
    window_id_(window_id),
    hwnd_(nullptr),
    on_close_callback_(std::move(on_close_callback)) {
}

WebviewWindow::~WebviewWindow() = default;

void WebviewWindow::CreateAndShow(const std::wstring &title, int height, int width, CreateCallback callback) {

  auto *window_class = GetWindowClass();

  // the same as flutter default main.cpp
  const POINT target_point = {static_cast<LONG>(10),
                              static_cast<LONG>(10)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);

  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // TODO centered the new window.
  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      CW_USEDEFAULT, CW_USEDEFAULT,
      Scale(width, scale_factor), Scale(height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    callback(false);
    return;
  }

  hwnd_ = window;

  ShowWindow(window, SW_SHOW);
  UpdateWindow(window);

  CreateCoreWebView2EnvironmentWithOptions(
      nullptr, L"webview_window_WebView2", nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, window, callback(std::move(callback))](HRESULT result,
                                                        ICoreWebView2Environment *env) -> HRESULT {
            if (!SUCCEEDED(result)) {
              callback(false);
              return S_OK;
            }
            env->CreateCoreWebView2Controller(
                window,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this, callback](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                      if (SUCCEEDED(result)) {
                        callback(true);
                        webview_controller_ =
                            controller;
                        OnWebviewControllerCreated();
                      } else {
                        callback(false);
                      }
                      return S_OK;
                    }).Get());
            return S_OK;
          }).Get());
}

void WebviewWindow::OnWebviewControllerCreated() {
  if (!webview_controller_) {
    return;
  }
  webview_controller_->get_CoreWebView2(&webview_);

  if (!webview_) {
    std::cerr << "failed to get core webview" << std::endl;
    return;
  }

  ICoreWebView2Settings *settings;
  webview_->get_Settings(&settings);
  settings->put_IsScriptEnabled(true);
  settings->put_IsZoomControlEnabled(false);
  settings->put_AreDefaultContextMenusEnabled(false);
  settings->put_IsStatusBarEnabled(false);

  // Resize WebView to fit the bounds of the parent window
  RECT bounds;
  GetClientRect(hwnd_, &bounds);
  webview_controller_->put_Bounds(bounds);

  // Always use single window to load web page.
  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2 *sender, ICoreWebView2NewWindowRequestedEventArgs *args) {
            args->put_NewWindow(sender);
            return S_OK;
          }).Get(), nullptr);

//  webview_->add_WebMessageReceived(
//      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
//          [](ICoreWebView2 *webview, ICoreWebView2WebMessageReceivedEventArgs *args) {
//            PWSTR message;
//
//            args->TryGetWebMessageAsString(&message);
//            std::wstring str(message);
//            std::cout << "message: " << wide_to_utf8(str) << std::endl;
//            CoTaskMemFree(message);
//            return S_OK;
//          }
//      ).Get(), nullptr);

}

void WebviewWindow::Navigate(const std::wstring &url) {
  if (webview_) {
    webview_->Navigate(url.c_str());
  }
}

void WebviewWindow::AddScriptToExecuteOnDocumentCreated(const std::wstring &javaScript) {
  if (webview_) {
    webview_->AddScriptToExecuteOnDocumentCreated(javaScript.c_str(), nullptr);
  }
}

void WebviewWindow::Close() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
  }
}

void WebviewWindow::SetBrightness(int brightness) {
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

    auto that = static_cast<WebviewWindow *>(window_struct->lpCreateParams);
    that->hwnd_ = window;
  } else if (WebviewWindow *that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam
    );
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
  switch (message) {
    case WM_DESTROY: {
      hwnd_ = nullptr;
      auto args = flutter::EncodableMap{
          {flutter::EncodableValue("id"), flutter::EncodableValue(window_id_)}
      };
      method_channel_->InvokeMethod(
          "onWindowClose",
          std::make_unique<flutter::EncodableValue>(args)
      );
      if (on_close_callback_) {
        on_close_callback_();
      }
      break;
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
      if (webview_controller_ != nullptr) {
        RECT bounds;
        GetClientRect(hwnd, &bounds);
        webview_controller_->put_Bounds(bounds);
      };
      return 0;
    }

    case WM_ACTIVATE:return 0;
  }

  return
      DefWindowProc(hwnd, message, wparam, lparam
      );
}

// static
WebviewWindow *WebviewWindow::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<WebviewWindow *>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

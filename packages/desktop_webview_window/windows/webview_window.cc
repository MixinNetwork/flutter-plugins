//
// Created by yangbin on 2021/10/20.
//

#include <windows.h>
#include <dwmapi.h>

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


using namespace Microsoft::WRL;

constexpr UINT kDeferredClose = WM_APP + 1;

}  // namespace

WebviewWindow::WebviewWindow(EventSink emit,
                             NavigationRequest request_navigation,
                             int64_t window_id,
                             std::function<void()> on_close_callback)
    : emit_(std::move(emit)),
      request_navigation_(std::move(request_navigation)),
      hwnd_(),
      window_id_(window_id),
      on_close_callback_(std::move(on_close_callback)) {}

WebviewWindow::~WebviewWindow() {
  // No callbacks may reenter a partially destructed window.
  if (hwnd_) {
    SetWindowLongPtr(hwnd_.get(), GWLP_USERDATA, 0);
  }
  if (!destroyed_) {
    closing_ = true;
    composer_.BeginClose();
    composer_.Closing(window_id_);
    dww::UnregisterBrowser(window_id_);
  }
  if (web_view_) {
    web_view_->Close();
    web_view_.reset();
  }
  hwnd_.reset();
}

void WebviewWindow::CreateAndShow(const Options& options,
                                  CreateCallback callback) {
  // Keep this alive through synchronous failure callbacks and window messages.
  auto keep_alive = shared_from_this();
  create_callback_ = std::move(callback);
  RegisterWindowClass(kWebViewWindowClassName, WebviewWindow::WndProc);

  // Size the window for the monitor it will open on: the requested position,
  // or the monitor showing the cursor for a centred window.
  POINT target_point = {static_cast<LONG>(options.x), static_cast<LONG>(options.y)};
  if (!options.use_position) GetCursorPos(&target_point);
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  DWORD style = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN;
  if (options.open_maximized) {
    style |= WS_MAXIMIZE;
  }
  hwnd_ = wil::unique_hwnd(::CreateWindow(
      kWebViewWindowClassName, options.title.c_str(), style,
      options.use_position ? options.x : CW_USEDEFAULT,
      options.use_position ? options.y : CW_USEDEFAULT,
      Scale(options.width, scale_factor), Scale(options.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this));
  if (!hwnd_) {
    CompleteCreation(CreateOutcome::kFailed, "Failed to create the browser window.");
    OnClosed();
    return;
  }
  SetBrightness(brightness_);
  if (!options.use_position && !options.open_maximized) {
    ClipOrCenterWindowToMonitor(hwnd_.get(), MONITOR_CENTER);
  }

  std::weak_ptr<WebviewWindow> weak = weak_from_this();
  web_view_ = std::make_shared<webview_window::WebView>(
      emit_, request_navigation_,
      [weak] {
        if (auto window = weak.lock()) window->PublishNavigationState();
      },
      window_id_, options.user_data_folder, options.deny_camera_and_microphone,
      options.javascript_bridge);
  web_view_->SetVisible(!options.open_hidden);
  HWND view = web_view_->NativeWindow().get();
  SetParent(view, hwnd_.get());

  dww::RegisterBrowser(window_id_, this);
  const DWWComposeRequest request{
      window_id_, hwnd_.get(), view,
      options.composer_arguments ? options.composer_arguments->c_str() : nullptr,
      options.title_bar};
  composer_.Compose(request);
  if (closing_) {
    DestroyNow();
    return;
  }
  Layout();
  ShowWindow(view, SW_SHOW);
  PublishNavigationState();
  if (closing_) {
    DestroyNow();
    return;
  }
  if (!options.open_hidden) {
    ShowWindow(hwnd_.get(), options.open_maximized ? SW_SHOWMAXIMIZED : SW_SHOW);
    UpdateWindow(hwnd_.get());
  }

  // Start asynchronous WebView2 initialization only after ownership, parenting
  // and composition. Closing now resolves the pending create as closed.
  web_view_->Create([weak](HRESULT result) {
    auto window = weak.lock();
    if (!window || window->destroyed_) {
      return;
    }
    if (SUCCEEDED(result)) {
      window->CompleteCreation(CreateOutcome::kReady);
      window->PublishNavigationState();
    } else {
      window->CompleteCreation(CreateOutcome::kFailed,
                               "Failed to initialize the browser view.");
      window->Close();
    }
  });
}

void WebviewWindow::CompleteCreation(CreateOutcome outcome,
                                     const std::string& error) {
  auto callback = std::exchange(create_callback_, nullptr);
  if (callback) {
    callback(outcome, error);
  }
}

bool WebviewWindow::Close() {
  if (closing_ || destroyed_) return false;
  closing_ = true;
  composer_.BeginClose();
  if (composer_.dispatching() && hwnd_) {
    // Composer code is on the stack; tear down once it has returned.
    PostMessage(hwnd_.get(), kDeferredClose, 0, 0);
    return true;
  }
  DestroyNow();
  return true;
}

void WebviewWindow::DestroyNow() {
  auto keep_alive = shared_from_this();
  if (destroyed_) return;
  closing_ = true;
  composer_.BeginClose();
  composer_.Closing(window_id_);
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
  closing_ = true;
  composer_.BeginClose();
  // Normally delivered by DestroyNow(); this covers an external destroy.
  composer_.Closing(window_id_);
  destroyed_ = true;
  dww::UnregisterBrowser(window_id_);
  if (web_view_) {
    web_view_->Close();
    web_view_.reset();
  }
  CompleteCreation(CreateOutcome::kClosed);
  if (emit_) {
    emit_("onWindowClose", flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(window_id_)}});
  }
  auto callback = std::exchange(on_close_callback_, nullptr);
  if (callback) {
    callback();
  }
}

bool WebviewWindow::GoBack() {
  if (closing_ || destroyed_) return false;
  if (web_view_) web_view_->GoBack();
  return true;
}

bool WebviewWindow::GoForward() {
  if (closing_ || destroyed_) return false;
  if (web_view_) web_view_->GoForward();
  return true;
}

bool WebviewWindow::Reload() {
  if (closing_ || destroyed_) return false;
  if (web_view_) web_view_->Reload();
  return true;
}

bool WebviewWindow::Stop() {
  if (closing_ || destroyed_) return false;
  if (web_view_) web_view_->Stop();
  return true;
}

void WebviewWindow::Layout() {
  if (!hwnd_ || !web_view_) return;
  RECT bounds;
  GetClientRect(hwnd_.get(), &bounds);
  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  if (!composer_.Layout(window_id_, width, height)) {
    MoveWindow(web_view_->NativeWindow().get(), 0, 0, width, height, TRUE);
  }
}

void WebviewWindow::PublishNavigationState() {
  if (closing_ || destroyed_ || !web_view_) return;
  auto state = web_view_->State();
  if (published_ && *published_ == state) return;
  published_ = state;
  const std::string url = wide_to_utf8(state.url);
  const std::string title = wide_to_utf8(state.title);
  auto text = [](const std::string& value) {
    return value.empty() ? flutter::EncodableValue()
                         : flutter::EncodableValue(value);
  };
  if (emit_) {
    emit_("onNavigationStateChanged", flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(window_id_)},
        {flutter::EncodableValue("canGoBack"), flutter::EncodableValue(state.can_go_back)},
        {flutter::EncodableValue("canGoForward"), flutter::EncodableValue(state.can_go_forward)},
        {flutter::EncodableValue("isLoading"), flutter::EncodableValue(state.is_loading)},
        {flutter::EncodableValue("url"), text(url)},
        {flutter::EncodableValue("title"), text(title)},
    });
  }
  const DWWNavigationState native{
      window_id_, state.can_go_back, state.can_go_forward, state.is_loading,
      url.empty() ? nullptr : url.c_str(),
      title.empty() ? nullptr : title.c_str()};
  composer_.NavigationChanged(native);
}

void WebviewWindow::SetBrightness(int brightness) {
  brightness_ = brightness;
  if (!hwnd_) return;
  BOOL dark = brightness == 0;
  if (brightness < 0) {
    DWORD light = 1;
    DWORD size = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
    dark = light == 0;
  }
  // Older Windows versions may not support this attribute; leave their native
  // titlebar unchanged in that case. 20 is DWMWA_USE_IMMERSIVE_DARK_MODE.
  DwmSetWindowAttribute(hwnd_.get(), static_cast<DWMWINDOWATTRIBUTE>(20),
                        &dark, sizeof(dark));
  // Read by the default toolbar.
  SetPropW(hwnd_.get(), L"DesktopWebviewDark",
           reinterpret_cast<HANDLE>(static_cast<INT_PTR>(dark ? 1 : 2)));
  RedrawWindow(hwnd_.get(), nullptr, nullptr,
               RDW_INVALIDATE | RDW_ALLCHILDREN);
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
  // Messages are not forwarded to the engine's top-level window delegates:
  // those belong to the application's windows (for example window_manager)
  // and must not act on browser windows.
  switch (message) {
    case WM_CLOSE:
      // The close button takes the same path as every other close request.
      Close();
      return 0;
    case kDeferredClose:
      DestroyNow();
      return 0;
    case WM_DESTROY: {
      // The OS is already destroying this HWND; do not destroy it a second time
      // when the final shared owner is released at the end of WndProc.
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      RemovePropW(hwnd, L"DesktopWebviewDark");
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
      Layout();
      return 0;
    }
    case WM_WINDOWPOSCHANGED: {
      // WebView2 does not follow its host window's visibility. Track it here,
      // including when another library shows or hides the window by handle.
      // Unlike WM_SHOWWINDOW, this is sent for every ShowWindow command.
      const auto* pos = reinterpret_cast<const WINDOWPOS*>(lparam);
      if (web_view_ && pos) {
        if (pos->flags & SWP_SHOWWINDOW) web_view_->SetVisible(true);
        if (pos->flags & SWP_HIDEWINDOW) web_view_->SetVisible(false);
      }
      // DefWindowProc still derives WM_SIZE and WM_MOVE from this message.
      break;
    }
    case WM_DWMCOLORIZATIONCOLORCHANGED:
    case WM_SETTINGCHANGE: {
      if (brightness_ == -1) SetBrightness(-1);
      break;
    }
    case WM_ACTIVATE: {
      // DefWindowProc would focus this frame window, which has no input of its
      // own. Hand activation focus to the page instead.
      if (LOWORD(wparam) != WA_INACTIVE && web_view_) {
        web_view_->Focus();
      }
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


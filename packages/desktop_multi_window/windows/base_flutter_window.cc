//
// Created by yangbin on 2022/1/27.
//

#include "base_flutter_window.h"

namespace {
  void CenterRectToMonitor(LPRECT prc) {
    HMONITOR hMonitor;
    MONITORINFO mi;
    RECT rc;
    int w = prc->right - prc->left;
    int h = prc->bottom - prc->top;

    //
    // get the nearest monitor to the passed rect.
    //
    hMonitor = MonitorFromRect(prc, MONITOR_DEFAULTTONEAREST);

    //
    // get the work area or entire monitor rect.
    //
    mi.cbSize = sizeof(mi);
    GetMonitorInfo(hMonitor, &mi);

    rc = mi.rcMonitor;

    prc->left = rc.left + (rc.right - rc.left - w) / 2;
    prc->top = rc.top + (rc.bottom - rc.top - h) / 2;
    prc->right = prc->left + w;
    prc->bottom = prc->top + h;

  }

  std::wstring Utf16FromUtf8(const std::string& string) {
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, string.c_str(), -1, nullptr, 0);
    if (size_needed == 0) {
      return {};
    }
    std::wstring wstrTo(size_needed, 0);
    int converted_length = MultiByteToWideChar(CP_UTF8, 0, string.c_str(), -1, &wstrTo[0], size_needed);
    if (converted_length == 0) {
      return {};
    }
    return wstrTo;
  }

  bool IsWindows11OrGreater() {
    DWORD dwVersion = 0;
    DWORD dwBuild = 0;

#pragma warning(push)
#pragma warning(disable : 4996)
    dwVersion = GetVersion();
    // Get the build number.
    if (dwVersion < 0x80000000)
      dwBuild = (DWORD)(HIWORD(dwVersion));
#pragma warning(pop)

    return dwBuild < 22000;
  }

  void adjustNCCALCSIZE(HWND hwnd, NCCALCSIZE_PARAMS* sz) {
    LONG l = 8;
    LONG t = 8;

    // HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    // Don't use `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)` above.
    // Because if the window is restored from minimized state, the window is not in the correct monitor.
    // The monitor is always the left-most monitor.
    // https://github.com/leanflutter/window_manager/issues/489
    HMONITOR monitor = MonitorFromRect(&sz->rgrc[0], MONITOR_DEFAULTTONEAREST);
    if (monitor != NULL) {
      MONITORINFO monitorInfo;
      monitorInfo.cbSize = sizeof(MONITORINFO);
      if (TRUE == GetMonitorInfo(monitor, &monitorInfo)) {
        l = sz->rgrc[0].left - monitorInfo.rcWork.left;
        t = sz->rgrc[0].top - monitorInfo.rcWork.top;
      } else {
        // GetMonitorInfo failed, use (8, 8) as default value
      }
    } else {
      // unreachable code
    }

    sz->rgrc[0].left -= l;
    sz->rgrc[0].top -= t;
    sz->rgrc[0].right += l;
    sz->rgrc[0].bottom += t;
  }


}

BaseFlutterWindow::BaseFlutterWindow() {}

BaseFlutterWindow::~BaseFlutterWindow() {
  if (window_proc_id) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id);
  }
}


void BaseFlutterWindow::Center() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  RECT rect;
  GetWindowRect(handle, &rect);
  CenterRectToMonitor(&rect);
  SetWindowPos(handle, nullptr, rect.left, rect.top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void BaseFlutterWindow::SetFrame(double_t left, double_t top, double_t width, double_t height, UINT flags) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }

  // // Get window styles
  // DWORD style = GetWindowLong(handle, GWL_STYLE);
  // DWORD exStyle = GetWindowLong(handle, GWL_EXSTYLE);

  // // Calculate the required window size to achieve the desired client area size
  // RECT rect = { 0, 0, static_cast<LONG>(width), static_cast<LONG>(height) };

  // // Adjust for window decorations (title bar, borders, etc.)
  // AdjustWindowRectEx(&rect, style, FALSE, exStyle);

  // int adjustedWidth = rect.right - rect.left;
  // int adjustedHeight = rect.bottom - rect.top;

  // Move and resize the window
  SetWindowPos(
    handle,
    NULL,
    static_cast<int>(left),
    static_cast<int>(top),
    static_cast<int>(width),
    static_cast<int>(height),
    SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED | flags
  );
}

void BaseFlutterWindow::SetBackgroundColor(Color backgroundColor) {
  // bool isTransparent = backgroundColor.a == 0 && backgroundColor.r == 0 && backgroundColor.g == 0 && backgroundColor.b == 0;
  bool isTransparent = true;

  HWND hWnd = GetRootWindowHandle();
  const HINSTANCE hModule = LoadLibrary(TEXT("user32.dll"));
  if (hModule) {
    typedef enum _ACCENT_STATE {
      ACCENT_DISABLED = 0,
      ACCENT_ENABLE_GRADIENT = 1,
      ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
      ACCENT_ENABLE_BLURBEHIND = 3,
      ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
      ACCENT_ENABLE_HOSTBACKDROP = 5,
      ACCENT_INVALID_STATE = 6
    } ACCENT_STATE;
    struct ACCENTPOLICY {
      int nAccentState;
      int nFlags;
      int nColor;
      int nAnimationId;
    };
    struct WINCOMPATTRDATA {
      int nAttribute;
      PVOID pData;
      ULONG ulDataSize;
    };
    typedef BOOL(WINAPI* pSetWindowCompositionAttribute)(HWND, WINCOMPATTRDATA*);
    const pSetWindowCompositionAttribute SetWindowCompositionAttribute = (pSetWindowCompositionAttribute)GetProcAddress(hModule, "SetWindowCompositionAttribute");
    if (SetWindowCompositionAttribute) {
      int32_t accent_state = isTransparent ? ACCENT_ENABLE_TRANSPARENTGRADIENT
        : ACCENT_ENABLE_GRADIENT;
      ACCENTPOLICY policy = {
          accent_state, 2,
          (int)backgroundColor.toABGR(),
          0 };
      WINCOMPATTRDATA data = { 19, &policy, sizeof(policy) };
      SetWindowCompositionAttribute(hWnd, &data);
    }
    FreeLibrary(hModule);
  }
}

void BaseFlutterWindow::SetOpacity(double opacity) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }

  long gwlExStyle = GetWindowLong(handle, GWL_EXSTYLE);
  SetWindowLong(handle, GWL_EXSTYLE, gwlExStyle | WS_EX_LAYERED);
  SetLayeredWindowAttributes(handle, 0, static_cast<BYTE>(opacity * 255), 0x02);
}

RECT BaseFlutterWindow::GetFrame() {
  HWND hwnd = GetRootWindowHandle();
  RECT rect;
  if (GetWindowRect(hwnd, &rect)) {
    return rect;
  }
  return {};
}

void BaseFlutterWindow::SetTitle(const std::string& title) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  SetWindowText(handle, Utf16FromUtf8(title).c_str());
}

void BaseFlutterWindow::Close() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  PostMessage(handle, WM_SYSCOMMAND, SC_CLOSE, 0);
}

void BaseFlutterWindow::Show() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  ShowWindow(handle, SW_SHOW);
}

void BaseFlutterWindow::Hide() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  ShowWindow(handle, SW_HIDE);
}

void BaseFlutterWindow::Focus() {
  HWND hWnd = GetRootWindowHandle();
  if (IsMinimized()) {
    Restore();
  }

  ::SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE);
  SetForegroundWindow(hWnd);
}

void BaseFlutterWindow::Blur() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  HWND next_hwnd = ::GetNextWindow(handle, GW_HWNDNEXT);
  while (next_hwnd) {
    if (::IsWindowVisible(next_hwnd)) {
      ::SetForegroundWindow(next_hwnd);
      return;
    }
    next_hwnd = ::GetNextWindow(next_hwnd, GW_HWNDNEXT);
  }
}

bool BaseFlutterWindow::IsFocused() {
  return GetRootWindowHandle() == GetForegroundWindow();
}

bool BaseFlutterWindow::IsVisible() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return false;
  }
  bool isVisible = IsWindowVisible(handle);
  return isVisible;
}

bool BaseFlutterWindow::IsMaximized() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return false;
  }
  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);

  return windowPlacement.showCmd == SW_MAXIMIZE;
}

bool BaseFlutterWindow::IsMinimized() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return false;
  }
  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);
  return windowPlacement.showCmd == SW_SHOWMINIMIZED;
}

void BaseFlutterWindow::Maximize(bool vertically) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);

  if (vertically) {
    POINT cursorPos;
    GetCursorPos(&cursorPos);
    PostMessage(handle, WM_NCLBUTTONDBLCLK, HTTOP,
      MAKELPARAM(cursorPos.x, cursorPos.y));
  } else {
    if (windowPlacement.showCmd != SW_MAXIMIZE) {
      PostMessage(handle, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    }
  }
}

void BaseFlutterWindow::Unmaximize() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);

  if (windowPlacement.showCmd != SW_NORMAL) {
    PostMessage(handle, WM_SYSCOMMAND, SC_RESTORE, 0);
  }
}

void BaseFlutterWindow::Minimize() {
  if (IsFullScreen()) {  // Like chromium, we don't want to minimize fullscreen
    // windows
    return;
  }
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);

  if (windowPlacement.showCmd != SW_SHOWMINIMIZED) {
    PostMessage(handle, WM_SYSCOMMAND, SC_MINIMIZE, 0);
  }
}

void BaseFlutterWindow::Restore() {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  WINDOWPLACEMENT windowPlacement;
  GetWindowPlacement(handle, &windowPlacement);

  if (windowPlacement.showCmd != SW_NORMAL) {
    PostMessage(handle, WM_SYSCOMMAND, SC_RESTORE, 0);
  }
}

bool BaseFlutterWindow::IsFullScreen() {
  return g_is_window_fullscreen;
}

void BaseFlutterWindow::SetFullScreen(bool is_full_screen) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }
  // Previously inspired by how Chromium does this
  // https://src.chromium.org/viewvc/chrome/trunk/src/ui/views/win/fullscreen_handler.cc?revision=247204&view=markup
  // Instead, we use a modified implementation of how the media_kit package
  // implements this (we got permission from the author, I believe)
  // https://github.com/alexmercerind/media_kit/blob/1226bcff36eab27cb17d60c33e9c15ca489c1f06/media_kit_video/windows/utils.cc

  // Save current window state if not already fullscreen.
  if (!g_is_window_fullscreen) {
    // Save current window information.
    g_maximized_before_fullscreen = ::IsZoomed(handle);
    g_style_before_fullscreen = GetWindowLong(handle, GWL_STYLE);
    ::GetWindowRect(handle, &g_frame_before_fullscreen);
    // g_title_bar_style_before_fullscreen = title_bar_style_;
  }

  g_is_window_fullscreen = is_full_screen;

  if (is_full_screen) {  // Set to fullscreen
    ::SendMessage(handle, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    // if (!is_frameless_) {
    //   auto monitor = MONITORINFO{};
    //   auto placement = WINDOWPLACEMENT{};
    //   monitor.cbSize = sizeof(MONITORINFO);
    //   placement.length = sizeof(WINDOWPLACEMENT);
    //   ::GetWindowPlacement(handle, &placement);
    //   ::GetMonitorInfo(
    //       ::MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST), &monitor);
    //   ::SetWindowLongPtr(handle, GWL_STYLE,
    //                      g_style_before_fullscreen & ~WS_OVERLAPPEDWINDOW);
    //   ::SetWindowPos(handle, HWND_TOP, monitor.rcMonitor.left,
    //                  monitor.rcMonitor.top,
    //                  monitor.rcMonitor.right - monitor.rcMonitor.left,
    //                  monitor.rcMonitor.bottom - monitor.rcMonitor.top,
    //                  SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    // }
  } else {  // Restore from fullscreen
    if (!g_maximized_before_fullscreen)
      Restore();
    ::SetWindowLongPtr(handle, GWL_STYLE,
      g_style_before_fullscreen | WS_OVERLAPPEDWINDOW);
    if (::IsZoomed(handle)) {
      // Refresh the parent mainWindow.
      ::SetWindowPos(handle, nullptr, 0, 0, 0, 0,
        SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
        SWP_FRAMECHANGED);
      auto rect = RECT{};
      ::GetClientRect(handle, &rect);
      auto flutter_view = ::FindWindowEx(handle, nullptr,
        kFlutterViewWindowClassName, nullptr);
      ::SetWindowPos(flutter_view, nullptr, rect.left, rect.top,
        rect.right - rect.left, rect.bottom - rect.top,
        SWP_NOACTIVATE | SWP_NOZORDER);
      if (g_maximized_before_fullscreen)
        PostMessage(handle, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    } else {
      ::SetWindowPos(
        handle, nullptr, g_frame_before_fullscreen.left,
        g_frame_before_fullscreen.top,
        g_frame_before_fullscreen.right - g_frame_before_fullscreen.left,
        g_frame_before_fullscreen.bottom - g_frame_before_fullscreen.top,
        SWP_NOACTIVATE | SWP_NOZORDER);
    }
  }
}

void BaseFlutterWindow::SetStyle(int32_t style, int32_t extended_style) {
  auto handle = GetRootWindowHandle();
  if (!handle) {
    return;
  }

  // Store current window position and size
  RECT windowRect;
  GetWindowRect(handle, &windowRect);

  // Store current visibility state
  bool wasVisible = IsWindowVisible(handle);
  bool wasMaximized = IsZoomed(handle);

  if (wasMaximized) {
    // Restore the window before changing styles if it's maximized
    ShowWindow(handle, SW_RESTORE);
  }

  // Set the new styles
  SetWindowLongPtr(handle, GWL_STYLE, style);
  SetWindowLongPtr(handle, GWL_EXSTYLE, extended_style);

  // Update the window's frame
  SetWindowPos(
    handle,
    nullptr,
    windowRect.left,
    windowRect.top,
    windowRect.right - windowRect.left,
    windowRect.bottom - windowRect.top,
    SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE |
    (wasVisible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW)
  );

  // Get the new client area
  // RECT newClientRect;
  // GetClientRect(handle, &newClientRect);

  // Find the Flutter view - try different class names that might be used
  // HWND flutterView = NULL;
  // const wchar_t* possibleClassNames[] = {
  //     L"FlutterMultiWindow",
  //     L"FLUTTER_RUNNER_WIN32_WINDOW",
  //     L"FLUTTERVIEW"
  // };

  // for (const auto& className : possibleClassNames) {
  //   flutterView = FindWindowEx(handle, NULL, className, NULL);
  //   if (flutterView) break;
  // }

  // // If we found the Flutter view, resize it to fill the client area
  // if (flutterView) {
  //   SetWindowPos(
  //     flutterView,
  //     NULL,
  //     0, 0,
  //     newClientRect.right, newClientRect.bottom,
  //     SWP_NOZORDER
  //   );
  // } else {
  //   // If we couldn't find the Flutter view by class name, try the first child window
  //   flutterView = GetWindow(handle, GW_CHILD);
  //   if (flutterView) {
  //     SetWindowPos(
  //       flutterView,
  //       NULL,
  //       0, 0,
  //       newClientRect.right, newClientRect.bottom,
  //       SWP_NOZORDER
  //     );
  //   }
  // }

  // Restore maximized state if needed
  if (wasMaximized) {
    ShowWindow(handle, SW_MAXIMIZE);
  }

  // Force a complete redraw
  RedrawWindow(handle, NULL, NULL, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME | RDW_ALLCHILDREN);
}

void BaseFlutterWindow::Destroy() {
  if (inter_window_event_channel_) {
    inter_window_event_channel_ = nullptr;
  }
  if (window_events_channel_) {
    window_events_channel_ = nullptr;
  }

  if (id_ != 0) {
    if (flutter_controller_) {
      flutter_controller_ = nullptr;
    }
    if (window_handle_) {
      DestroyWindow(window_handle_);
      window_handle_ = nullptr;
    }
  }
}

void BaseFlutterWindow::_EmitEvent(std::string eventName)
{
  if (window_events_channel_ == nullptr) {
    return;
  }
  flutter::EncodableMap args = flutter::EncodableMap();
  args[flutter::EncodableValue("eventName")] = flutter::EncodableValue(eventName);
  window_events_channel_->channel_->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
}

bool BaseFlutterWindow::MessageHandler(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(hWnd, message, wParam, lParam);
    if (result) {
      return *result;
    }
  }
  std::optional<LRESULT> result = HandleWindowProc(hWnd, message, wParam, lParam);
  if (result) {
    return *result;
  }
  return DefWindowProc(window_handle_, message, wParam, lParam);
}

std::optional<LRESULT> BaseFlutterWindow::HandleWindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{

  auto child_content_ = flutter_controller_ ? flutter_controller_->view()->GetNativeWindow() : nullptr;

  std::optional<LRESULT> result = std::nullopt;

  switch (message) {
  case WM_FONTCHANGE: {
    if (flutter_controller_) {
      flutter_controller_->engine()->ReloadSystemFonts();
      return true;
    }
    break;
  }
  case WM_DESTROY: {
    Destroy();
    if (!destroyed_) {
      destroyed_ = true;
      if (auto callback = callback_.lock()) {
        callback->OnWindowDestroy(id_);
      }
    }
    break;
  }
  case WM_CLOSE: {
    if (auto callback = callback_.lock()) {
      callback->OnWindowClose(id_);
    }
    _EmitEvent("close");
    break;
  }
  case WM_DPICHANGED: {
    auto newRectSize = reinterpret_cast<RECT*>(lParam);
    LONG newWidth = newRectSize->right - newRectSize->left;
    LONG newHeight = newRectSize->bottom - newRectSize->top;

    SetWindowPos(hWnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
      newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

    return true;
  }
  case WM_SIZE: {
    if (IsFullScreen() && wParam == SIZE_MAXIMIZED &&
      last_state != STATE_FULLSCREEN_ENTERED) {
      _EmitEvent("enter-full-screen");
      last_state = STATE_FULLSCREEN_ENTERED;
    } else if (!IsFullScreen() && wParam == SIZE_RESTORED &&
      last_state == STATE_FULLSCREEN_ENTERED) {
      _EmitEvent("leave-full-screen");
      last_state = STATE_NORMAL;
    } else if (last_state != STATE_FULLSCREEN_ENTERED) {
      if (wParam == SIZE_MAXIMIZED) {
        _EmitEvent("maximize");
        last_state = STATE_MAXIMIZED;
      } else if (wParam == SIZE_MINIMIZED) {
        _EmitEvent("minimize");
        last_state = STATE_MINIMIZED;
        return 0;
      } else if (wParam == SIZE_RESTORED) {
        if (last_state == STATE_MAXIMIZED) {
          _EmitEvent("unmaximize");
          last_state = STATE_NORMAL;
        } else if (last_state == STATE_MINIMIZED) {
          _EmitEvent("restore");
          last_state = STATE_NORMAL;
        }
      }
    }

    if (child_content_ != nullptr) {
      RECT rect;
      GetClientRect(hWnd, &rect);
      MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
        rect.bottom - rect.top, TRUE);
      return true;
    }
    break;
  }
  case WM_NCACTIVATE: {
    if (wParam == 0) {
      _EmitEvent("blur");
    } else {
      _EmitEvent("focus");
    }
    break;
  }
  case WM_ACTIVATE: {

    // // Extract activation state from the low-order word
    // UINT activationState = LOWORD(wparam);

    // // Check if the window is minimized (nonzero high-order word)
    // BOOL isMinimized = HIWORD(wparam) != 0;

    // switch (activationState) {
    // case WA_INACTIVE:
    //   // Handle deactivation
    //   std::cerr << "deactivate" << std::endl;
    //   break;
    // case WA_ACTIVE:
    //   // Handle activation (without mouse click)
    //   std::cerr << "activate" << std::endl;
    //   break;
    // case WA_CLICKACTIVE:
    //   // Handle activation (with mouse click)
    //   std::cerr << "click-activate" << std::endl;
    //   break;
    // default:
    //   break;
    // }

    // // You can also use the 'isMinimized' flag as needed
    // if (isMinimized) {
    //   // The window was minimized.
    // }
    if (child_content_ != nullptr) {
      SetFocus(child_content_);
      return true;
    }
    break;
  }
  case WM_EXITSIZEMOVE: {
    if (is_resizing_) {
      _EmitEvent("resized");
      is_resizing_ = false;
    }
    if (is_moving_) {
      _EmitEvent("moved");
      is_moving_ = false;
    }
    break;
  }
  case WM_MOVING: {
    is_moving_ = true;
    _EmitEvent("move");
    break;
  }
  case WM_SIZING: {
    is_resizing_ = true;
    _EmitEvent("resize");
    if (aspect_ratio_ > 0) {
      RECT* rect = (LPRECT)lParam;

      double aspect_ratio = aspect_ratio_;

      int new_width = static_cast<int>(rect->right - rect->left);
      int new_height = static_cast<int>(rect->bottom - rect->top);

      bool is_resizing_horizontally =
        wParam == WMSZ_LEFT || wParam == WMSZ_RIGHT ||
        wParam == WMSZ_TOPLEFT || wParam == WMSZ_BOTTOMLEFT;

      if (is_resizing_horizontally) {
        new_height = static_cast<int>(new_width / aspect_ratio);
      } else {
        new_width = static_cast<int>(new_height * aspect_ratio);
      }

      int left = rect->left;
      int top = rect->top;
      int right = rect->right;
      int bottom = rect->bottom;

      switch (wParam) {
      case WMSZ_RIGHT:
      case WMSZ_BOTTOM:
        right = new_width + left;
        bottom = top + new_height;
        break;
      case WMSZ_TOP:
        right = new_width + left;
        top = bottom - new_height;
        break;
      case WMSZ_LEFT:
      case WMSZ_TOPLEFT:
        left = right - new_width;
        top = bottom - new_height;
        break;
      case WMSZ_TOPRIGHT:
        right = left + new_width;
        top = bottom - new_height;
        break;
      case WMSZ_BOTTOMLEFT:
        left = right - new_width;
        bottom = top + new_height;
        break;
      case WMSZ_BOTTOMRIGHT:
        right = left + new_width;
        bottom = top + new_height;
        break;
      }

      rect->left = left;
      rect->top = top;
      rect->right = right;
      rect->bottom = bottom;
    }
    break;
  }
  case WM_SHOWWINDOW: {
    if (wParam == TRUE) {
      _EmitEvent("show");
    } else {
      _EmitEvent("hide");
    }
    break;
  }
  default: {
    // std::cerr << "default" << std::endl;
  }
  }
  return result;
}
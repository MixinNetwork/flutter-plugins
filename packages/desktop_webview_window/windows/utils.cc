//
// Created by yangbin on 2021/11/11.
//

#include "utils.h"

#include <windows.h>

#include <memory>
#include <set>
#include <string>

namespace webview_window {

void ClipOrCenterRectToMonitor(LPRECT prc, UINT flags) {
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

  if (flags & MONITOR_WORKAREA)
    rc = mi.rcWork;
  else
    rc = mi.rcMonitor;

  //
  // center or clip the passed rect to the monitor rect
  //
  if (flags & MONITOR_CENTER) {
    prc->left = rc.left + (rc.right - rc.left - w) / 2;
    prc->top = rc.top + (rc.bottom - rc.top - h) / 2;
    prc->right = prc->left + w;
    prc->bottom = prc->top + h;
  } else {
    prc->left = max(rc.left, min(rc.right - w, prc->left));
    prc->top = max(rc.top, min(rc.bottom - h, prc->top));
    prc->right = prc->left + w;
    prc->bottom = prc->top + h;
  }
}

void ClipOrCenterWindowToMonitor(HWND hwnd, UINT flags) {
  RECT rc;
  GetWindowRect(hwnd, &rc);
  ClipOrCenterRectToMonitor(&rc, flags);
  SetWindowPos(hwnd, nullptr, rc.left, rc.top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

bool SetWindowBackgroundTransparent(HWND hwnd) {
  // TODO
  return false;
}

static std::unique_ptr<std::set<LPCWSTR>> class_registered_;

struct AppIconRequest {
  int width;
  int height;
  HICON icon;
};

static BOOL CALLBACK LoadFirstIconGroup(HMODULE module, LPCWSTR, LPWSTR name,
                                        LONG_PTR param) {
  // |name| is only valid during enumeration, so load the icon here.
  auto request = reinterpret_cast<AppIconRequest *>(param);
  request->icon = static_cast<HICON>(LoadImageW(
      module, name, IMAGE_ICON, request->width, request->height, 0));
  return FALSE;
}

// Loads the host executable's first icon group, the icon Explorer and the
// taskbar show for the app, at the system size for |metric_x|/|metric_y|.
static HICON LoadAppIcon(HINSTANCE instance, int metric_x, int metric_y) {
  AppIconRequest request{GetSystemMetrics(metric_x),
                         GetSystemMetrics(metric_y), nullptr};
  EnumResourceNamesW(instance, RT_GROUP_ICON, LoadFirstIconGroup,
                     reinterpret_cast<LONG_PTR>(&request));
  return request.icon ? request.icon : LoadIcon(nullptr, IDI_APPLICATION);
}

const wchar_t *RegisterWindowClass(LPCWSTR class_name, WNDPROC wnd_proc) {
  if (!class_registered_ || class_registered_->count(class_name) == 0) {
    if (!class_registered_) {
      class_registered_ = std::make_unique<std::set<LPCWSTR>>();
    }
    WNDCLASSEX window_class{};
    window_class.cbSize = sizeof(WNDCLASSEX);
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = class_name;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadAppIcon(window_class.hInstance, SM_CXICON, SM_CYICON);
    window_class.hIconSm =
        LoadAppIcon(window_class.hInstance, SM_CXSMICON, SM_CYSMICON);
    window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = wnd_proc;
    RegisterClassEx(&window_class);
    class_registered_->insert(class_name);
  }
  return class_name;
}

void UnregisterWindowClass(LPCWSTR class_name) {
  if (!class_registered_) {
    return;
  }
  class_registered_->erase(class_name);
  UnregisterClass(class_name, nullptr);
}

std::string ConvertLPCWSTRToString(LPCWSTR lpcwszStr) {
  int strLength = WideCharToMultiByte(CP_UTF8, 0, lpcwszStr, -1, nullptr, 0,
                                      nullptr, nullptr);
  std::string str(strLength, 0);

  WideCharToMultiByte(CP_UTF8, 0, lpcwszStr, -1, &str[0], strLength, nullptr,
                      nullptr);
  return str;
}

}  // namespace webview_window
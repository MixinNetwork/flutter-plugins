//
// Created by yangbin on 2021/11/11.
//

#include <windows.h>

#include "utils.h"

#include <memory>
#include <set>

namespace {

// https://github.com/alexmercerind/flutter_acrylic/blob/master/windows/flutter_acrylic_plugin.cpp
// flutter_acrylic_plugin BEGIN

typedef enum _WINDOWCOMPOSITIONATTRIB {
  WCA_UNDEFINED = 0,
  WCA_NCRENDERING_ENABLED = 1,
  WCA_NCRENDERING_POLICY = 2,
  WCA_TRANSITIONS_FORCEDISABLED = 3,
  WCA_ALLOW_NCPAINT = 4,
  WCA_CAPTION_BUTTON_BOUNDS = 5,
  WCA_NONCLIENT_RTL_LAYOUT = 6,
  WCA_FORCE_ICONIC_REPRESENTATION = 7,
  WCA_EXTENDED_FRAME_BOUNDS = 8,
  WCA_HAS_ICONIC_BITMAP = 9,
  WCA_THEME_ATTRIBUTES = 10,
  WCA_NCRENDERING_EXILED = 11,
  WCA_NCADORNMENTINFO = 12,
  WCA_EXCLUDED_FROM_LIVEPREVIEW = 13,
  WCA_VIDEO_OVERLAY_ACTIVE = 14,
  WCA_FORCE_ACTIVEWINDOW_APPEARANCE = 15,
  WCA_DISALLOW_PEEK = 16,
  WCA_CLOAK = 17,
  WCA_CLOAKED = 18,
  WCA_ACCENT_POLICY = 19,
  WCA_FREEZE_REPRESENTATION = 20,
  WCA_EVER_UNCLOAKED = 21,
  WCA_VISUAL_OWNER = 22,
  WCA_HOLOGRAPHIC = 23,
  WCA_EXCLUDED_FROM_DDA = 24,
  WCA_PASSIVEUPDATEMODE = 25,
  WCA_USEDARKMODECOLORS = 26,
  WCA_LAST = 27
} WINDOWCOMPOSITIONATTRIB;

typedef struct _WINDOWCOMPOSITIONATTRIBDATA {
  WINDOWCOMPOSITIONATTRIB Attrib;
  PVOID pvData;
  SIZE_T cbData;
} WINDOWCOMPOSITIONATTRIBDATA;

typedef enum _ACCENT_STATE {
  ACCENT_DISABLED = 0,
  ACCENT_ENABLE_GRADIENT = 1,
  ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
  ACCENT_ENABLE_BLURBEHIND = 3,
  ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
  ACCENT_ENABLE_HOSTBACKDROP = 5,
  ACCENT_INVALID_STATE = 6
} ACCENT_STATE;

typedef struct _ACCENT_POLICY {
  ACCENT_STATE AccentState;
  DWORD AccentFlags;
  DWORD GradientColor;
  DWORD AnimationId;
} ACCENT_POLICY;

typedef BOOL(WINAPI *GetWindowCompositionAttribute)(
    HWND, WINDOWCOMPOSITIONATTRIBDATA *);
typedef BOOL(WINAPI *SetWindowCompositionAttribute)(
    HWND, WINDOWCOMPOSITIONATTRIBDATA *);

typedef LONG NTSTATUS, *PNTSTATUS;
#define STATUS_SUCCESS (0x00000000)

typedef NTSTATUS(WINAPI *RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);


// flutter_acrylic_plugin END

HMODULE user32 = nullptr;

SetWindowCompositionAttribute set_window_composition_attribute_ = nullptr;

}

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
  SetWindowPos(hwnd, nullptr, rc.left, rc.top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

bool SetWindowBackgroundTransparent(HWND hwnd) {
  if (user32 == nullptr) {
    user32 = GetModuleHandleA("user32.dll");
    if (user32 == nullptr) {
      return false;
    }
    set_window_composition_attribute_ =
        reinterpret_cast<SetWindowCompositionAttribute>(
            ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
    if (!set_window_composition_attribute_) {
      return false;
    }
  }

  ACCENT_POLICY accent = {
      ACCENT_ENABLE_TRANSPARENTGRADIENT, 2,
      0,
      0};
  WINDOWCOMPOSITIONATTRIBDATA data;
  data.Attrib = WCA_ACCENT_POLICY;
  data.pvData = &accent;
  data.cbData = sizeof(accent);
  set_window_composition_attribute_(hwnd, &data);

  return true;
}

static std::unique_ptr<std::set<LPCWSTR>> class_registered_;

const wchar_t *RegisterWindowClass(LPCWSTR class_name, WNDPROC wnd_proc) {
  if (!class_registered_ || class_registered_->count(class_name) == 0) {
    if (!class_registered_) {
      class_registered_ = std::make_unique<std::set<LPCWSTR>>();
    }
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = class_name;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, IDI_APPLICATION);
    window_class.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = wnd_proc;
    RegisterClass(&window_class);
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

}  // namespace webview_window
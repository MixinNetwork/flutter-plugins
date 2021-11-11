//
// Created by yangbin on 2021/11/11.
//

#include <windows.h>

#include "utils.h"

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

}
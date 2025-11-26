//
// Created by chuishui233 on 2025/09/26.
//

#ifndef DESKTOP_WEBVIEW_WINDOW_WINDOWS_UTILS_H_
#define DESKTOP_WEBVIEW_WINDOW_WINDOWS_UTILS_H_

#include <windows.h>
#include "wil/wrl.h"
#include <string>

namespace webview_window {

const auto MONITOR_CENTER = 0x0001;        // center rect to monitor
const auto MONITOR_CLIP = 0x0000;      // clip rect to monitor
const auto MONITOR_WORKAREA = 0x0002;        // use monitor work area
const auto MONITOR_AREA = 0x0000;        // use monitor entire area

//
//  ClipOrCenterRectToMonitor
//
//  The most common problem apps have when running on a
//  multimonitor system is that they "clip" or "pin" windows
//  based on the SM_CXSCREEN and SM_CYSCREEN system metrics.
//  Because of app compatibility reasons these system metrics
//  return the size of the primary monitor.
//
//  This shows how you use the multi-monitor functions
//  to do the same thing.
//
void ClipOrCenterRectToMonitor(LPRECT prc, UINT flags);

void ClipOrCenterWindowToMonitor(HWND hwnd, UINT flags);

bool SetWindowBackgroundTransparent(HWND hwnd);

const wchar_t *RegisterWindowClass(LPCWSTR class_name, WNDPROC wnd_proc, const std::wstring &iconPath = L"");

void UnregisterWindowClass(LPCWSTR class_name);

}  // namespace webview_window

#endif //DESKTOP_WEBVIEW_WINDOW_WINDOWS_UTILS_H_

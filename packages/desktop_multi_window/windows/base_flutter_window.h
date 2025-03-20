//
// Created by yangbin on 2022/1/27.
//

#ifndef MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H_
#define MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H_

#include <flutter/flutter_view_controller.h>

#include "inter_window_event_channel.h"
#include "window_events_channel.h"
#include "window_options.h"

enum WindowState {
  STATE_NORMAL,
  STATE_MAXIMIZED,
  STATE_MINIMIZED,
  STATE_FULLSCREEN_ENTERED,
  STATE_DOCKED,
};

class BaseFlutterWindowCallback {

public:
  virtual void OnWindowClose(int64_t id) = 0;

  virtual void OnWindowDestroy(int64_t id) = 0;

};

class BaseFlutterWindow
{

public:

  BaseFlutterWindow();
  ~BaseFlutterWindow();

  InterWindowEventChannel* GetInterWindowEventChannel() {
    return inter_window_event_channel_.get();
  }

  WindowEventsChannel* GetWindowEventsChannel() {
    return window_events_channel_.get();
  }

  HWND GetRootWindowHandle() {
    if (!root_window_handle_ || !IsWindow(root_window_handle_)) {
      root_window_handle_ = GetAncestor(window_handle_, GA_ROOT);
    }
    return root_window_handle_;
  }

  bool IsDestroyed() {
    return destroyed_;
  }

  bool IsClosed() {
    return closed_;
  }

  void Show();

  void Hide();

  void Close();

  void SetTitle(const std::string& title);

  RECT GetFrame();

  void SetFrame(double_t x, double_t y, double_t width, double_t height, UINT flags);

  void SetBackgroundColor(Color backgroundColor);

  void SetOpacity(double opacity);

  // void SetMinSize(double_t width, double_t height);

  // void SetMaxSize(double_t width, double_t height);

  bool IsFocused();

  bool IsFullScreen();

  bool IsMaximized();

  bool IsMinimized();

  bool IsVisible();

  void Focus();

  void Blur();

  void Maximize(bool vertically);

  void Unmaximize();

  void Minimize();

  void Restore();

  void SetFullScreen(bool is_full_screen);

  void SetStyle(int32_t style, int32_t extended_style);

  void SetIgnoreMouseEvents(bool ignore);

  void Center();

  std::optional<LRESULT> HandleWindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam);


protected:


  int64_t id_;

  HWND window_handle_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  flutter::PluginRegistrarWindows* registrar_;

  std::unique_ptr<InterWindowEventChannel> inter_window_event_channel_;

  std::unique_ptr<WindowEventsChannel> window_events_channel_;

  HWND GetWindowHandle() {
    return window_handle_;
  }

  int window_proc_id = 0;

  void _EmitEvent(std::string eventName);

  bool MessageHandler(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam);

  std::weak_ptr<BaseFlutterWindowCallback> callback_;

  bool destroyed_ = false;

  bool closed_ = false;

  void Destroy();

private:

  static constexpr auto kFlutterViewWindowClassName = L"FlutterMultiWindow";
  bool g_is_window_fullscreen = false;
  std::string g_title_bar_style_before_fullscreen;
  RECT g_frame_before_fullscreen;
  bool g_maximized_before_fullscreen;
  LONG g_style_before_fullscreen;

  HWND root_window_handle_;

  double aspect_ratio_ = 0;

  bool is_moving_ = false;
  bool is_resizing_ = false;

  WindowState last_state = STATE_NORMAL;

};

#endif // MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H

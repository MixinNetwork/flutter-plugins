//
// Created by yangbin on 2022/1/11.
//

#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <Windows.h>

#include <flutter/flutter_view_controller.h>

#include <cstdint>
#include <memory>

#include "base_flutter_window.h"
#include "inter_window_event_channel.h"
#include "window_options.h"


class FlutterWindow : public BaseFlutterWindow {

public:
  FlutterWindow(
    int64_t id,
    std::string args,
    const std::shared_ptr<BaseFlutterWindowCallback>& callback,
    WindowOptions options
  );

  ~FlutterWindow();

private:

  double scale_factor_;

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

  static FlutterWindow* GetThisFromHandle(HWND window) noexcept;

};

#endif // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

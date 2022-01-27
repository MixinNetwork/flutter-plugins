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
#include "window_channel.h"

class FlutterWindowCallback {

 public:
  virtual void OnWindowClose(int64_t id) = 0;

  virtual void OnWindowDestroy(int64_t id) = 0;

};

class FlutterWindow : public BaseFlutterWindow {

 public:

  FlutterWindow(int64_t id, std::string args, const std::shared_ptr<FlutterWindowCallback> &callback);
  ~FlutterWindow() override;

  WindowChannel *GetWindowChannel() override {
    return window_channel_.get();
  }

 protected:

  HWND GetWindowHandle() override { return window_handle_; }

 private:

  std::weak_ptr<FlutterWindowCallback> callback_;

  HWND window_handle_;

  int64_t id_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<WindowChannel> window_channel_;

  double scale_factor_;

  bool destroyed_ = false;

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

  static FlutterWindow *GetThisFromHandle(HWND window) noexcept;

  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  void Destroy();
};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

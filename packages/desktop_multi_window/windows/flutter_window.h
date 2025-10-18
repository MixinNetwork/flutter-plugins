#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <Windows.h>

#include <flutter/flutter_view_controller.h>

#include <cstdint>
#include <memory>
#include <string>

#include "base_flutter_window.h"

class FlutterWindowCallback {

 public:
  virtual void OnWindowClose(const std::string& id) = 0;

  virtual void OnWindowDestroy(const std::string& id) = 0;

};

class FlutterWindow : public BaseFlutterWindow {

 public:

  FlutterWindow(const std::string& id, std::string args, const std::shared_ptr<FlutterWindowCallback> &callback);
  ~FlutterWindow() override;

  std::string GetWindowId() const override {
    return id_;
  }

  std::string GetWindowArgument() const override {
    return window_argument_;
  }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) override;

 protected:

  HWND GetWindowHandle() override { return window_handle_; }

 private:

  std::weak_ptr<FlutterWindowCallback> callback_;

  HWND window_handle_;

  std::string id_;
  std::string window_argument_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  double scale_factor_;

  bool destroyed_ = false;

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

  static FlutterWindow *GetThisFromHandle(HWND window) noexcept;

  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  void Destroy();
};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

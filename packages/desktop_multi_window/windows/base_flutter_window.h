#ifndef MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H_
#define MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H_

#include <Windows.h>
#include <memory>
#include <string>

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>

class BaseFlutterWindow {
 public:
  virtual ~BaseFlutterWindow() = default;

  virtual std::string GetWindowId() const = 0;

  virtual std::string GetWindowArgument() const = 0;

  virtual void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
          result) = 0;

  void Show();

  void Hide();

  virtual HWND GetWindowHandle() = 0;
};

#endif  // MULTI_WINDOW_WINDOWS_BASE_FLUTTER_WINDOW_H_

#include "flutter_window.h"

#include <optional>
#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
#ifndef NDEBUG
  // Example-only fixture: inspect the real DWM attribute rather than a cached
  // plugin value. Integration test window titles are ASCII.
  flutter::MethodChannel<flutter::EncodableValue> test_channel(
      flutter_controller_->engine()->messenger(), "webview_example/native_test",
      &flutter::StandardMethodCodec::GetInstance());
  test_channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "inspect") {
      result->NotImplemented();
      return;
    }
    const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
    const auto& title = std::get<std::string>(args.at(flutter::EncodableValue("title")));
    const auto window = FindWindowA("WebviewWindow", title.c_str());
    BOOL dark = FALSE;
    if (!window || FAILED(DwmGetWindowAttribute(window,
            static_cast<DWMWINDOWATTRIBUTE>(20), &dark, sizeof(dark)))) {
      result->Error("test_window_missing", "Cannot inspect native titlebar appearance");
      return;
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("nativeDark"), flutter::EncodableValue(dark != FALSE)},
    }));
  });
#endif
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

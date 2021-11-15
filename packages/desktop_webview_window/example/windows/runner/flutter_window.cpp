#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_webview_window/desktop_webview_window_plugin.h"

namespace {

class WebviewWindowAdapterImpl : public WebviewWindowAdapter {

 public:

  std::unique_ptr<flutter::FlutterViewController> CreateViewController(
      int width,
      int height,
      const flutter::DartProject &project) override {
    return std::make_unique<flutter::FlutterViewController>(width, height, project);
  }

  std::optional<LRESULT> HandleTopLevelWindowProc(
      const std::unique_ptr<flutter::FlutterViewController> &flutter_view_controller,
      HWND hwnd,
      UINT message,
      WPARAM wparam,
      LPARAM lparam) override {
    return flutter_view_controller->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
  }

  void ReloadSystemFonts(const std::unique_ptr<flutter::FlutterViewController> &flutter_view_controller) override {
    flutter_view_controller->engine()->ReloadSystemFonts();
  }

};

}


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
  SetFlutterViewControllerFactory(std::make_unique<WebviewWindowAdapterImpl>());
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

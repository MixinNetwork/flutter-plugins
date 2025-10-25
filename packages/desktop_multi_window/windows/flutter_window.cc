#include "flutter_window.h"

#include "flutter_windows.h"

#include "tchar.h"

#include <iostream>

#include "multi_window_manager.h"
#include "multi_window_plugin_internal.h"

FlutterWindow::FlutterWindow(const std::string& id,
                             const WindowConfiguration config)
    : id_(id), window_argument_(config.arguments) {}

bool FlutterWindow::OnCreate() {
  // Called when the window is created
  RECT frame = GetClientArea();

  flutter::DartProject project(L"data");
  std::vector<std::string> entrypoint_args = {"multi_window", id_,
                                              window_argument_};
  project.set_dart_entrypoint_arguments(entrypoint_args);
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);

  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
    return false;
  }

  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view_handle);

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  MultiWindowManager::Instance()->RemoveManagedFlutterWindowLater(id_);
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
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

FlutterWindow::~FlutterWindow() {
  // Cleanup is handled by Win32Window::Destroy()
}

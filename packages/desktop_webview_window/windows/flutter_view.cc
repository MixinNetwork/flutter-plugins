//
// Created by yangbin on 2021/11/12.
//

#include <windows.h>
#include "flutter_view.h"

#include <cassert>
#include <iostream>

#include "include/desktop_webview_window/desktop_webview_window_plugin.h"
#include "utils.h"
#include "message_channel_plugin.h"

namespace {

std::unique_ptr<WebviewWindowAdapter> flutter_webview_window_adapter;

}

namespace webview_window {

FlutterView::FlutterView(std::vector<std::string> arguments) {

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(arguments));
  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = flutter_webview_window_adapter->CreateViewController(0, 0, project);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup Flutter engine." << std::endl;
    return;
  }
  RegisterClientMessageChannelPlugin(flutter_controller_->engine()->GetRegistrarForPlugin("DesktopWebviewWindowPlugin"));
}

FlutterView::~FlutterView() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
}

std::optional<LRESULT> FlutterView::HandleTopLevelWindowProc(HWND hwnd, UINT message, WPARAM w_param, LPARAM l_param) {
  return flutter_webview_window_adapter->HandleTopLevelWindowProc(flutter_controller_, hwnd, message, w_param, l_param);
}

void FlutterView::ReloadSystemFonts() {
  flutter_webview_window_adapter->ReloadSystemFonts(flutter_controller_);
}

void FlutterView::ForceRedraw() {
}

}

void SetFlutterViewControllerFactory(std::unique_ptr<WebviewWindowAdapter> adapter) {
  assert(adapter != nullptr);
  assert(flutter_webview_window_adapter == nullptr);
  flutter_webview_window_adapter = std::move(adapter);
}

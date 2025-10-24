#include "base_flutter_window.h"

void BaseFlutterWindow::SetChannel(std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel) {
  channel_ = channel;
}

void BaseFlutterWindow::NotifyWindowEvent(const std::string& event, const flutter::EncodableMap& data) {
  if (channel_) {
    channel_->InvokeMethod(event, std::make_unique<flutter::EncodableValue>(data));
  }
}

void BaseFlutterWindow::Show() {
  auto handle = GetWindowHandle();
  if (!handle) {
    return;
  }
  ShowWindow(handle, SW_SHOW);
}

void BaseFlutterWindow::Hide() {
  auto handle = GetWindowHandle();
  if (!handle) {
    return;
  }
  ShowWindow(handle, SW_HIDE);
}

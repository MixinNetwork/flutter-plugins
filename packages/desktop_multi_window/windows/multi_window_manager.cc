//
// Created by yangbin on 2022/1/11.
//

#include "multi_window_manager.h"

#include <memory>

#include "flutter_window.h"

namespace {
int64_t g_next_id_ = 0;

class FlutterMainWindow : public BaseFlutterWindow {

 public:

  FlutterMainWindow(HWND hwnd, std::unique_ptr<WindowChannel> window_channel)
      : hwnd_(hwnd), channel_(std::move(window_channel)) {

  }

  ~FlutterMainWindow() override = default;

  WindowChannel *GetWindowChannel() override {
    return channel_.get();
  }

 protected:

  HWND GetWindowHandle() override {
    return hwnd_;
  }

 private:

  HWND hwnd_;

  std::unique_ptr<WindowChannel> channel_;

};

}

// static
MultiWindowManager *MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {

}

int64_t MultiWindowManager::Create(std::string args) {
  g_next_id_++;
  int64_t id = g_next_id_;

  auto window = std::make_unique<FlutterWindow>(id, std::move(args), shared_from_this());
  auto channel = window->GetWindowChannel();
  channel->SetMethodCallHandler([this](int64_t from_window_id,
                                       int64_t target_window_id,
                                       const std::string &call,
                                       flutter::EncodableValue *arguments,
                                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    HandleWindowChannelCall(from_window_id, target_window_id, call, arguments, std::move(result));
  });
  windows_[id] = std::move(window);
  return id;
}

void MultiWindowManager::AttachFlutterMainWindow(
    HWND main_window_handle,
    std::unique_ptr<WindowChannel> window_channel) {
  if (windows_.count(0) != 0) {
    std::cout << "Error: main window already exists" << std::endl;
    return;
  }
  window_channel->SetMethodCallHandler(
      [this](int64_t from_window_id,
             int64_t target_window_id,
             const std::string &call,
             flutter::EncodableValue *arguments,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleWindowChannelCall(from_window_id, target_window_id, call, arguments, std::move(result));
      });
  windows_[0] = std::make_unique<FlutterMainWindow>(main_window_handle, std::move(window_channel));
}

void MultiWindowManager::Show(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Show();
  }
}

void MultiWindowManager::Hide(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Hide();
  }
}

void MultiWindowManager::Close(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Close();
  }
}

void MultiWindowManager::SetFrame(int64_t id, double x, double y, double width, double height) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetBounds(x, y, width, height);
  }
}

void MultiWindowManager::SetTitle(int64_t id, const std::string &title) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetTitle(title);
  }
}

void MultiWindowManager::Center(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Center();
  }
}

flutter::EncodableList MultiWindowManager::GetAllSubWindowIds() {
  flutter::EncodableList resList = flutter::EncodableList();
  for (auto &window : windows_) {
    if (window.first != 0) {
      resList.push_back(flutter::EncodableValue(window.first));
    }
  }
  return resList;
}

void MultiWindowManager::OnWindowClose(int64_t id) {
}

void MultiWindowManager::OnWindowDestroy(int64_t id) {
  windows_.erase(id);
}

void MultiWindowManager::HandleWindowChannelCall(
    int64_t from_window_id,
    int64_t target_window_id,
    const std::string &call,
    flutter::EncodableValue *arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result
) {
  auto target_window_entry = windows_.find(target_window_id);
  if (target_window_entry == windows_.end()) {
    result->Error("-1", "target window not found.");
    return;
  }
  auto target_window_channel = target_window_entry->second->GetWindowChannel();
  if (!target_window_channel) {
    result->Error("-1", "target window channel not found.");
    return;
  }
  target_window_channel->InvokeMethod(from_window_id, call, arguments, std::move(result));
}


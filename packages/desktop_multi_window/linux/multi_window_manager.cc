//
// Created by yangbin on 2022/1/11.
//

#include "multi_window_manager.h"

namespace {
int64_t g_next_id_ = 0;

class FlutterMainWindow : public BaseFlutterWindow {

 public:

  FlutterMainWindow(GtkWidget *window, std::unique_ptr<WindowChannel> window_channel)
      : window_channel_(std::move(window_channel)), window_(window) {}

  WindowChannel *GetWindowChannel() override {
    return window_channel_.get();
  }
 protected:
  GtkWindow *GetWindow() override {
    return GTK_WINDOW(window_);
  }

 private:
  std::unique_ptr<WindowChannel> window_channel_;
  GtkWidget *window_;

};

}

// static
MultiWindowManager *MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {

}

MultiWindowManager::~MultiWindowManager() = default;

int64_t MultiWindowManager::Create(const std::string &args) {
  g_next_id_++;
  int64_t id = g_next_id_;
  auto window = std::make_unique<FlutterWindow>(id, args, shared_from_this());
  window->GetWindowChannel()->SetMethodHandler([this](int64_t from_window_id,
                                                      int64_t target_window_id,
                                                      const gchar *method,
                                                      FlValue *arguments,
                                                      FlMethodCall *method_call) {
    HandleMethodCall(from_window_id, target_window_id, method, arguments, method_call);
  });
  windows_[id] = std::move(window);
  return id;
}

void MultiWindowManager::AttachMainWindow(GtkWidget *main_flutter_window,
                                          std::unique_ptr<WindowChannel> window_channel) {
  if (windows_.count(0) != 0) {
    g_critical("AttachMainWindow : main window already exists.");
    return;
  }
  window_channel->SetMethodHandler([this](int64_t from_window_id,
                                          int64_t target_window_id,
                                          const gchar *method,
                                          FlValue *arguments,
                                          FlMethodCall *method_call) {
    HandleMethodCall(from_window_id, target_window_id, method, arguments, method_call);
  });
  windows_[0] = std::make_unique<FlutterMainWindow>(main_flutter_window, std::move(window_channel));
}

void MultiWindowManager::HandleMethodCall(int64_t from_window_id,
                                          int64_t target_window_id,
                                          const gchar *method,
                                          FlValue *arguments,
                                          FlMethodCall *method_call
) {
  if (windows_.count(target_window_id) == 0) {
    fl_method_call_respond_error(method_call, "-1", "target window not found.", nullptr, nullptr);
    return;
  }
  auto window_channel = windows_[target_window_id]->GetWindowChannel();
  if (!window_channel) {
    fl_method_call_respond_error(method_call, "-1", "target window channel not found.", nullptr, nullptr);
    return;
  }
  window_channel->InvokeMethod(from_window_id, method, arguments, method_call);
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

std::vector<int64_t> MultiWindowManager::GetAllSubWindowIds() {
  std::vector<int64_t> ids;
  for (auto &window : windows_) {
    if (window.first != 0) {
      ids.push_back(window.first);
    }
  }
  return ids;
}

void MultiWindowManager::Center(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Center();
  }
}

void MultiWindowManager::OnWindowClose(int64_t id) {
}

void MultiWindowManager::OnWindowDestroy(int64_t id) {
  windows_.erase(id);
}


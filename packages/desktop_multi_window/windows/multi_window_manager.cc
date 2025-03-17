//
// Created by yangbin on 2022/1/11.
//

#include "inter_window_event_channel.h"
#include "multi_window_manager.h"

#include <memory>
#include <thread>
#include <mutex>

namespace {
  int64_t g_next_id_ = 0;
  std::mutex threadMtx;

  class FlutterMainWindow : public BaseFlutterWindow {

  public:
    FlutterMainWindow(HWND hwnd,
      const std::shared_ptr<BaseFlutterWindowCallback>& callback,
      std::unique_ptr<InterWindowEventChannel> inter_window_event_channel,
      std::unique_ptr<WindowEventsChannel> window_events_channel,
      flutter::PluginRegistrarWindows* registrar) {
      window_handle_ = hwnd;
      id_ = 0;
      callback_ = callback;
      inter_window_event_channel_ = std::move(inter_window_event_channel);
      window_events_channel_ = std::move(window_events_channel);
      registrar_ = registrar;
      window_proc_id = registrar->RegisterTopLevelWindowProcDelegate(
        [this](HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
        return HandleWindowProc(hWnd, message, wParam, lParam);
      });
    }
  };

}

// static
MultiWindowManager* MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {
}

int64_t MultiWindowManager::Create(std::string args, WindowOptions options) {
  std::lock_guard<std::mutex> lock(threadMtx);
  g_next_id_++;
  int64_t id = g_next_id_;

  auto window = std::make_unique<FlutterWindow>(id, std::move(args), shared_from_this(), options);
  auto channel = window->GetInterWindowEventChannel();
  channel->SetMethodCallHandler([this](int64_t from_window_id,
    int64_t target_window_id,
    const std::string& call,
    flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  { HandleWindowChannelCall(from_window_id, target_window_id, call, arguments, std::move(result)); });
  windows_[id] = std::move(window);
  return id;
}

void MultiWindowManager::AttachFlutterMainWindow(
  HWND main_window_handle,
  std::unique_ptr<InterWindowEventChannel> inter_window_event_channel,
  std::unique_ptr<WindowEventsChannel> window_events_channel,
  flutter::PluginRegistrarWindows* registrar) {
  std::lock_guard<std::mutex> lock(threadMtx);
  if (windows_.count(0) != 0) {
    std::cout << "Error: main window already exists" << std::endl;
    return;
  }
  inter_window_event_channel->SetMethodCallHandler(
    [this](int64_t from_window_id,
      int64_t target_window_id,
      const std::string& call,
      flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    HandleWindowChannelCall(from_window_id, target_window_id, call, arguments, std::move(result));
  });
  auto main_window = std::make_unique<FlutterMainWindow>(
    main_window_handle,
    shared_from_this(),
    std::move(inter_window_event_channel),
    std::move(window_events_channel),
    registrar
  );
  windows_[0] = std::move(main_window);
}

void MultiWindowManager::Show(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Show();
  }
}

void MultiWindowManager::Hide(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Hide();
  }
}

void MultiWindowManager::Close(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Close();
  }
}

void MultiWindowManager::SetFrame(int64_t id, double_t left, double_t top, double_t width, double_t height, UINT flags) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetFrame(left, top, width, height, flags);
  }
}

flutter::EncodableMap MultiWindowManager::GetFrame(int64_t id, double_t devicePixelRatio) {
  std::lock_guard<std::mutex> lock(threadMtx);
  flutter::EncodableMap resultMap = flutter::EncodableMap();
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    auto rect = window->second->GetFrame();
    double x = rect.left / devicePixelRatio * 1.0f;
    double y = rect.top / devicePixelRatio * 1.0f;
    double width = (rect.right - rect.left) / devicePixelRatio * 1.0f;
    double height = (rect.bottom - rect.top) / devicePixelRatio * 1.0f;

    resultMap[flutter::EncodableValue("left")] = flutter::EncodableValue(x);
    resultMap[flutter::EncodableValue("top")] = flutter::EncodableValue(y);
    resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
    resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
  }
  return resultMap;
}


void MultiWindowManager::SetTitle(int64_t id, const std::string& title) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetTitle(title);
  }
}

void MultiWindowManager::Center(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Center();
  }
}

bool MultiWindowManager::IsFocused(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    return window->second->IsFocused();
  }
  return false;
}

bool MultiWindowManager::IsFullScreen(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    return window->second->IsFullScreen();
  }
  return false;
}

bool MultiWindowManager::IsMaximized(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    return window->second->IsMaximized();
  }
  return false;
}

bool MultiWindowManager::IsMinimized(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    return window->second->IsMinimized();
  } return false;
}

bool MultiWindowManager::IsVisible(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    return window->second->IsVisible();
  }
  return false;
}

void MultiWindowManager::Maximize(int64_t id, bool vertically) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Maximize(vertically);
  }
}

void MultiWindowManager::Unmaximize(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Unmaximize();
  }
}

void MultiWindowManager::Minimize(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Minimize();
  }
}

void MultiWindowManager::Restore(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Restore();
  }
}

void MultiWindowManager::SetFullScreen(int64_t id, bool is_full_screen) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetFullScreen(is_full_screen);
  }
}

void MultiWindowManager::SetStyle(int64_t id, int32_t style, int32_t extended_style) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetStyle(style, extended_style);
  }
}

void MultiWindowManager::SetBackgroundColor(int64_t id, Color backgroundColor) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetBackgroundColor(backgroundColor);
  }
}

flutter::EncodableList MultiWindowManager::GetAllSubWindowIds() {
  std::lock_guard<std::mutex> lock(threadMtx);
  flutter::EncodableList resList = flutter::EncodableList();
  for (auto& window : windows_) {
    if (window.first != 0) {
      resList.push_back(flutter::EncodableValue(window.first));
    }
  }
  return resList;
}

void MultiWindowManager::OnWindowClose(int64_t id) {}

void MultiWindowManager::OnWindowDestroy(int64_t id) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    std::thread([this, id]() {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));

      std::lock_guard<std::mutex> delete_lock(threadMtx);
      if (windows_.find(id) != windows_.end()) {
        windows_.erase(id);
      }
    }).detach();
  }
}

void MultiWindowManager::HandleWindowChannelCall(
  int64_t from_window_id,
  int64_t target_window_id,
  const std::string& call,
  flutter::EncodableValue* arguments,
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::lock_guard<std::mutex> lock(threadMtx);
  auto target_window_entry = windows_.find(target_window_id);
  if (target_window_entry == windows_.end()) {
    result->Error("-1", "target window not found.");
    return;
  }
  auto target_window_channel = target_window_entry->second->GetInterWindowEventChannel();
  if (!target_window_channel) {
    result->Error("-1", "target window channel not found.");
    return;
  }
  target_window_channel->InvokeMethod(from_window_id, call, arguments, std::move(result));
}
#include "multi_window_manager.h"

#include <rpc.h>
#include <iomanip>
#include <memory>
#include <random>
#include <sstream>
#pragma comment(lib, "rpcrt4.lib")

#include <iostream>
#include "flutter_window.h"
#include "multi_window_plugin_internal.h"
#include "window_configuration.h"

namespace {

std::string GenerateWindowId() {
  UUID uuid;
  UuidCreate(&uuid);

  RPC_CSTR uuid_str = nullptr;
  UuidToStringA(&uuid, &uuid_str);

  std::string result(reinterpret_cast<char*>(uuid_str));
  RpcStringFreeA(&uuid_str);

  return result;
}

class FlutterMainWindow : public BaseFlutterWindow {
 public:
  FlutterMainWindow(const std::string& window_id,
                    HWND hwnd,
                    FlutterDesktopPluginRegistrarRef registrar)
      : window_id_(window_id), hwnd_(hwnd), registrar_(registrar) {}

  ~FlutterMainWindow() override = default;

  std::string GetWindowId() const override { return window_id_; }

  std::string GetWindowArgument() const override { return ""; }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
      override {
    if (method == "window_show") {
      Show();
      result->Success();
    } else if (method == "window_hide") {
      Hide();
      result->Success();
    } else {
      result->Error("-1", "unknown method: " + method);
    }
  }

 protected:
  HWND GetWindowHandle() override { return hwnd_; }

 private:
  std::string window_id_;
  HWND hwnd_;
  FlutterDesktopPluginRegistrarRef registrar_;
};

}  // namespace

// static
MultiWindowManager* MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {}

std::string MultiWindowManager::Create(const flutter::EncodableMap* args) {
  std::string window_id = GenerateWindowId();
  WindowConfiguration config = WindowConfiguration::FromEncodableMap(args);
  auto window =
      std::make_unique<FlutterWindow>(window_id, config, shared_from_this());
  windows_[window_id] = std::move(window);
  static_cast<FlutterWindow*>(windows_[window_id].get())->Initialize(config);
  
  // Notify all windows about the change
  NotifyWindowsChanged();
  
  return window_id;
}

void MultiWindowManager::AttachFlutterMainWindow(
    HWND window_handle,
    FlutterDesktopPluginRegistrarRef registrar) {
  // check if  window already exists
  for (const auto& [id, window] : windows_) {
    if (GetAncestor(window->GetWindowHandle(), GA_ROOT) == window_handle) {
      std::cout << "Main window already attached: " << id << std::endl;
      return;
    }
  }

  const std::string window_id = GenerateWindowId();
  auto window =
      std::make_unique<FlutterMainWindow>(window_id, window_handle, registrar);
  windows_[window_id] = std::move(window);

  InternalMultiWindowPluginRegisterWithRegistrar(registrar,
                                                 windows_[window_id].get());
  
  // Notify all windows about the change
  NotifyWindowsChanged();
}

BaseFlutterWindow* MultiWindowManager::GetWindow(const std::string& window_id) {
  auto it = windows_.find(window_id);
  if (it != windows_.end()) {
    return it->second.get();
  }
  return nullptr;
}

flutter::EncodableList MultiWindowManager::GetAllWindows() {
  flutter::EncodableList windows;
  for (const auto& [id, window] : windows_) {
    flutter::EncodableMap window_info;
    window_info[flutter::EncodableValue("windowId")] =
        flutter::EncodableValue(window->GetWindowId());
    window_info[flutter::EncodableValue("windowArgument")] =
        flutter::EncodableValue(window->GetWindowArgument());
    windows.push_back(flutter::EncodableValue(window_info));
  }
  return windows;
}

std::vector<std::string> MultiWindowManager::GetAllWindowIds() {
  std::vector<std::string> window_ids;
  for (const auto& [id, window] : windows_) {
    window_ids.push_back(id);
  }
  return window_ids;
}

void MultiWindowManager::NotifyWindowsChanged() {
  auto window_ids = GetAllWindowIds();
  flutter::EncodableList window_ids_list;
  for (const auto& id : window_ids) {
    window_ids_list.push_back(flutter::EncodableValue(id));
  }
  
  flutter::EncodableMap data;
  data[flutter::EncodableValue("windowIds")] = flutter::EncodableValue(window_ids_list);
  
  for (const auto& [id, window] : windows_) {
    window->NotifyWindowEvent("onWindowsChanged", data);
  }
}

void MultiWindowManager::OnWindowClose(const std::string& id) {}

void MultiWindowManager::OnWindowDestroy(const std::string& id) {
  std::cout << "Window destroyed: " << id << std::endl;
  windows_.erase(id);
  NotifyWindowsChanged();
}

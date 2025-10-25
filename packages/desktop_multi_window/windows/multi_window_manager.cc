#include "multi_window_manager.h"

#include <rpc.h>
#include <iomanip>
#include <memory>
#include <random>
#include <sstream>
#pragma comment(lib, "rpcrt4.lib")

#include <iostream>
#include "flutter_window.h"
#include "flutter_window_wrapper.h"
#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"
#include "win32_window.h"
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

WindowCreatedCallback _g_window_created_callback = nullptr;

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

  auto flutter_window = std::make_unique<FlutterWindow>(window_id, config);

  std::wstring title = L"";
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(800, 600);

  if (!flutter_window->Create(title, origin, size)) {
    std::cerr << "Failed to create window." << std::endl;
    return "";
  }

  ::ShowWindow(flutter_window->GetHandle(),
               config.hidden_at_launch ? SW_HIDE : SW_SHOW);

  auto wrapper = std::make_unique<FlutterWindowWrapper>(
      window_id, flutter_window->GetHandle(), config.arguments);

  windows_[window_id] = std::move(wrapper);

  if (_g_window_created_callback) {
    _g_window_created_callback(flutter_window->GetFlutterViewController());
  }
  auto registrar = flutter_window->GetFlutterViewController()
                       ->engine()
                       ->GetRegistrarForPlugin("DesktopMultiWindowPlugin");
  InternalMultiWindowPluginRegisterWithRegistrar(registrar,
                                                 windows_[window_id].get());

  // keep flutter_window alive
  managed_flutter_windows_[window_id] = std::move(flutter_window);

  // Notify all windows about the change
  NotifyWindowsChanged();

  CleanupRemovedWindows();

  return window_id;
}

void MultiWindowManager::AttachFlutterMainWindow(
    HWND window_handle,
    FlutterDesktopPluginRegistrarRef registrar) {
  // check if window already exists
  for (const auto& [id, window] : windows_) {
    if (GetAncestor(window->GetWindowHandle(), GA_ROOT) == window_handle) {
      return;
    }
  }

  const std::string window_id = GenerateWindowId();
  auto wrapper =
      std::make_unique<FlutterWindowWrapper>(window_id, window_handle);

  windows_[window_id] = std::move(wrapper);

  InternalMultiWindowPluginRegisterWithRegistrar(registrar,
                                                 windows_[window_id].get());

  // Notify all windows about the change
  NotifyWindowsChanged();
}

FlutterWindowWrapper* MultiWindowManager::GetWindow(
    const std::string& window_id) {
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

void MultiWindowManager::RemoveWindow(const std::string& window_id) {
  auto it = windows_.find(window_id);
  if (it != windows_.end()) {
    windows_.erase(it);
    NotifyWindowsChanged();
  }
  
  // quit application if no windows left
  if (windows_.empty()) {
    PostQuitMessage(0);
  }
}

void MultiWindowManager::RemoveManagedFlutterWindowLater(
    const std::string& window_id) {
  pending_remove_ids_.push_back(window_id);
}

// FIXME:maybe need a more robust way to cleanup removed windows
void MultiWindowManager::CleanupRemovedWindows() {
  for (auto& id : pending_remove_ids_) {
    auto it = managed_flutter_windows_.find(id);
    if (it != managed_flutter_windows_.end()) {
      std::cout << "Destroyed managed flutter window: " << id << std::endl;
      managed_flutter_windows_.erase(it);
    }
  }
  pending_remove_ids_.clear();
}

void MultiWindowManager::NotifyWindowsChanged() {
  auto window_ids = GetAllWindowIds();
  flutter::EncodableList window_ids_list;
  for (const auto& id : window_ids) {
    window_ids_list.push_back(flutter::EncodableValue(id));
  }

  flutter::EncodableMap data;
  data[flutter::EncodableValue("windowIds")] =
      flutter::EncodableValue(window_ids_list);

  for (const auto& [id, window] : windows_) {
    window->NotifyWindowEvent("onWindowsChanged", data);
  }
}

void DesktopMultiWindowSetWindowCreatedCallback(
    WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}
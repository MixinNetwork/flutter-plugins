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
}

BaseFlutterWindow* MultiWindowManager::GetWindow(const std::string& window_id) {
  auto it = windows_.find(window_id);
  if (it != windows_.end()) {
    return it->second.get();
  }
  return nullptr;
}

void MultiWindowManager::OnWindowClose(const std::string& id) {}

void MultiWindowManager::OnWindowDestroy(const std::string& id) {
  windows_.erase(id);
}

#include "multi_window_manager.h"

#include <memory>
#include <sstream>
#include <iomanip>
#include <random>

#include "flutter_window.h"
#include "multi_window_plugin_internal.h"

namespace {

std::string GenerateWindowId() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<> dis(0, 15);
  std::uniform_int_distribution<> dis2(8, 11);

  std::stringstream ss;
  ss << std::hex;
  for (int i = 0; i < 8; i++) {
    ss << dis(gen);
  }
  ss << "-";
  for (int i = 0; i < 4; i++) {
    ss << dis(gen);
  }
  ss << "-4"; // UUID version 4
  for (int i = 0; i < 3; i++) {
    ss << dis(gen);
  }
  ss << "-";
  ss << dis2(gen);
  for (int i = 0; i < 3; i++) {
    ss << dis(gen);
  }
  ss << "-";
  for (int i = 0; i < 12; i++) {
    ss << dis(gen);
  }
  return ss.str();
}

class FlutterMainWindow : public BaseFlutterWindow {

 public:

  FlutterMainWindow(const std::string& window_id, HWND hwnd, FlutterDesktopPluginRegistrarRef registrar)
      : window_id_(window_id), hwnd_(hwnd), registrar_(registrar) {

  }

  ~FlutterMainWindow() override = default;

  std::string GetWindowId() const override {
    return window_id_;
  }

  std::string GetWindowArgument() const override {
    return "";
  }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) override {
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

  HWND GetWindowHandle() override {
    return hwnd_;
  }

 private:

  std::string window_id_;
  HWND hwnd_;
  FlutterDesktopPluginRegistrarRef registrar_;

};

}

// static
MultiWindowManager *MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {

}

std::string MultiWindowManager::Create(std::string args) {
  std::string window_id = GenerateWindowId();

  auto window = std::make_unique<FlutterWindow>(window_id, std::move(args), shared_from_this());
  windows_[window_id] = std::move(window);
  return window_id;
}

void MultiWindowManager::AttachFlutterMainWindow(
    HWND main_window_handle,
    FlutterDesktopPluginRegistrarRef registrar) {
  const std::string main_window_id = GenerateWindowId();
  if (windows_.count(main_window_id) != 0) {
    std::cout << "Error: main window already exists" << std::endl;
    return;
  }
  auto window = std::make_unique<FlutterMainWindow>(main_window_id, main_window_handle, registrar);
  windows_[main_window_id] = std::move(window);
  
  InternalMultiWindowPluginRegisterWithRegistrar(registrar, windows_[main_window_id].get());
}

BaseFlutterWindow* MultiWindowManager::GetWindow(const std::string& window_id) {
  auto it = windows_.find(window_id);
  if (it != windows_.end()) {
    return it->second.get();
  }
  return nullptr;
}

void MultiWindowManager::OnWindowClose(const std::string& id) {
}

void MultiWindowManager::OnWindowDestroy(const std::string& id) {
  windows_.erase(id);
}


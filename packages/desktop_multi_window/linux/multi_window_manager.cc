#include "multi_window_manager.h"

#include <random>
#include <sstream>
#include <iomanip>

#include "flutter_window.h"
#include "desktop_multi_window_plugin_internal.h"

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

  FlutterMainWindow(const std::string& window_id, GtkWidget *window, FlPluginRegistrar *registrar)
      : window_id_(window_id), window_(window), registrar_(registrar) {}

  std::string GetWindowId() const override {
    return window_id_;
  }

  std::string GetWindowArgument() const override {
    return "";
  }

  void HandleWindowMethod(
      const gchar* method,
      FlValue* arguments,
      FlMethodCall* method_call) override {
    g_autoptr(FlMethodResponse) response = nullptr;
    
    if (strcmp(method, "window_show") == 0) {
      Show();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (strcmp(method, "window_hide") == 0) {
      Hide();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      g_autofree gchar* error_msg = g_strdup_printf("unknown method: %s", method);
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("-1", error_msg, nullptr));
    }
    
    fl_method_call_respond(method_call, response, nullptr);
  }

 protected:
  GtkWindow *GetWindow() override {
    return GTK_WINDOW(window_);
  }

 private:
  std::string window_id_;
  GtkWidget *window_;
  FlPluginRegistrar *registrar_;

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

std::string MultiWindowManager::Create(const std::string &args) {
  std::string window_id = GenerateWindowId();
  auto window = std::make_unique<FlutterWindow>(window_id, args, shared_from_this());
  windows_[window_id] = std::move(window);
  return window_id;
}

void MultiWindowManager::AttachMainWindow(GtkWidget *main_flutter_window,
                                          FlPluginRegistrar *registrar) {
  const std::string main_window_id = GenerateWindowId();
  if (windows_.count(main_window_id) != 0) {
    g_critical("AttachMainWindow : main window already exists.");
    return;
  }
  auto window = std::make_unique<FlutterMainWindow>(main_window_id, main_flutter_window, registrar);
  windows_[main_window_id] = std::move(window);
  
  desktop_multi_window_plugin_register_with_registrar_internal(registrar, windows_[main_window_id].get());
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


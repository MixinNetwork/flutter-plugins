#include "multi_window_manager.h"

#include <iomanip>
#include <random>
#include <sstream>

#include "desktop_multi_window_plugin_internal.h"
#include "flutter_window.h"
#include "window_configuration.h"
#include "include/desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

std::string GenerateWindowId() {
  std::random_device rd;
  std::mt19937_64 gen(rd());
  std::uniform_int_distribution<uint64_t> dis;

  uint64_t part1 = dis(gen);
  uint64_t part2 = dis(gen);

  part1 = (part1 & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;  // 版本 4
  part2 = (part2 & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;  // 变体

  char uuid_str[37];
  snprintf(uuid_str, sizeof(uuid_str), "%08x-%04x-%04x-%04x-%012llx",
           static_cast<uint32_t>(part1 >> 32),
           static_cast<uint16_t>(part1 >> 16), static_cast<uint16_t>(part1),
           static_cast<uint16_t>(part2 >> 48), part2 & 0xFFFFFFFFFFFFULL);

  return std::string(uuid_str);
}

WindowCreatedCallback _g_window_created_callback = nullptr;

}  // namespace

// static
MultiWindowManager* MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {}

MultiWindowManager::~MultiWindowManager() = default;

std::string MultiWindowManager::Create(FlValue* args) {
  WindowConfiguration config = WindowConfiguration::FromFlValue(args);
  std::string window_id = GenerateWindowId();
  
  // Create GTK window
  GtkWidget* gtk_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(gtk_window), 1280, 720);
  gtk_window_set_title(GTK_WINDOW(gtk_window), "");
  gtk_window_set_position(GTK_WINDOW(gtk_window), GTK_WIN_POS_CENTER);
  gtk_widget_show(GTK_WIDGET(gtk_window));

  // Setup destroy signal handler
  g_signal_connect(gtk_window, "destroy",
                   G_CALLBACK(+[](GtkWidget*, gpointer arg) {
                     auto* window_id_ptr = static_cast<std::string*>(arg);
                     MultiWindowManager::Instance()->OnWindowClose(*window_id_ptr);
                     MultiWindowManager::Instance()->OnWindowDestroy(*window_id_ptr);
                     delete window_id_ptr;
                   }),
                   new std::string(window_id));

  // Setup Flutter project
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char* entrypoint_args[] = {"multi_window", window_id.c_str(),
                                   config.arguments.c_str(), nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<char**>(entrypoint_args));

  // Create Flutter view
  auto fl_view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(fl_view));
  gtk_container_add(GTK_CONTAINER(gtk_window), GTK_WIDGET(fl_view));

  // Call window created callback
  if (_g_window_created_callback) {
    _g_window_created_callback(FL_PLUGIN_REGISTRY(fl_view));
  }

  // Register plugin
  g_autoptr(FlPluginRegistrar) desktop_multi_window_registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(fl_view),
                                                  "DesktopMultiWindowPlugin");

  // Create FlutterWindow instance
  auto window = std::make_unique<FlutterWindow>(window_id, config.arguments, gtk_window);
  windows_[window_id] = std::move(window);

  desktop_multi_window_plugin_register_with_registrar_internal(
      desktop_multi_window_registrar, windows_[window_id].get());

  gtk_widget_grab_focus(GTK_WIDGET(fl_view));

  if (config.hidden_at_launch) {
    gtk_widget_hide(GTK_WIDGET(gtk_window));
  }

  return window_id;
}

void MultiWindowManager::AttachMainWindow(GtkWidget* window_widget,
                                          FlPluginRegistrar* registrar) {
  // check window widget is in windows_
  for (const auto& pair : windows_) {
    if (pair.second->GetWindow() == GTK_WINDOW(window_widget)) {
      g_critical("AttachMainWindow : main window already exists.");
      return;
    }
  }

  const std::string main_window_id = GenerateWindowId();
  auto window = std::make_unique<FlutterWindow>(main_window_id, "", window_widget);
  windows_[main_window_id] = std::move(window);

  desktop_multi_window_plugin_register_with_registrar_internal(
      registrar, windows_[main_window_id].get());
}

FlutterWindow* MultiWindowManager::GetWindow(const std::string& window_id) {
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

void desktop_multi_window_plugin_set_window_created_callback(
    WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}

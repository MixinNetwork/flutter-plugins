#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "multi_window_manager.h"

namespace {

class DesktopMultiWindowPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DesktopMultiWindowPlugin(BaseFlutterWindow* window);

  ~DesktopMultiWindowPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  BaseFlutterWindow* window_;
};

// static
void DesktopMultiWindowPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  // This method is not used anymore, we use InternalMultiWindowPluginRegisterWithRegistrar instead
}

DesktopMultiWindowPlugin::DesktopMultiWindowPlugin(BaseFlutterWindow* window) 
    : window_(window) {}

DesktopMultiWindowPlugin::~DesktopMultiWindowPlugin() = default;

void DesktopMultiWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  // Check if this is a window-specific method (starts with "window_")
  const auto& method = method_call.method_name();
  if (method.rfind("window_", 0) == 0) {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto window_id = std::get<std::string>(arguments->at(flutter::EncodableValue("windowId")));
    
    auto window = MultiWindowManager::Instance()->GetWindow(window_id);
    if (!window) {
      result->Error("-1", "failed to find target window: " + window_id);
      return;
    }
    
    window->HandleWindowMethod(method, arguments, std::move(result));
    return;
  }
  
  if (method == "createWindow") {
    auto args = std::get_if<std::string>(method_call.arguments());
    auto window_id = MultiWindowManager::Instance()->Create(args != nullptr ? *args : "");
    result->Success(flutter::EncodableValue(window_id));
    return;
  } else if (method == "getWindowDefinition") {
    flutter::EncodableMap definition;
    definition[flutter::EncodableValue("windowId")] = flutter::EncodableValue(window_->GetWindowId());
    definition[flutter::EncodableValue("windowArgument")] = flutter::EncodableValue(window_->GetWindowArgument());
    result->Success(flutter::EncodableValue(definition));
    return;
  }
  
  result->NotImplemented();
}

}  // namespace

void DesktopMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {

  InternalMultiWindowPluginRegisterWithRegistrar(registrar);

  // Attach MainWindow
  auto hwnd = FlutterDesktopViewGetHWND(FlutterDesktopPluginRegistrarGetView(registrar));
  MultiWindowManager::Instance()->AttachFlutterMainWindow(GetAncestor(hwnd, GA_ROOT), registrar);
}

void InternalMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar,
    BaseFlutterWindow* window) {
  auto plugin_registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          plugin_registrar->messenger(), "mixin.one/desktop_multi_window",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopMultiWindowPlugin>(window);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  plugin_registrar->AddPlugin(std::move(plugin));
}

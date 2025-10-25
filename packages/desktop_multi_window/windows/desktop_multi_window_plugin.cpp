#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "flutter_window_wrapper.h"
#include "multi_window_manager.h"
#include "window_channel_plugin.h"

namespace {

class DesktopMultiWindowPlugin : public flutter::Plugin {
 public:
  DesktopMultiWindowPlugin(FlutterWindowWrapper* window,
                           flutter::PluginRegistrarWindows* registrar);

  ~DesktopMultiWindowPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  FlutterWindowWrapper* window_;
  flutter::PluginRegistrarWindows* registrar_;
};

DesktopMultiWindowPlugin::DesktopMultiWindowPlugin(
    FlutterWindowWrapper* window,
    flutter::PluginRegistrarWindows* registrar)
    : window_(window), registrar_(registrar) {
  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "mixin.one/desktop_multi_window",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  // Set channel to window for event notifications
  window_->SetChannel(channel);

  // Register WindowChannel plugin for each engine
  WindowChannelPluginRegisterWithRegistrar(registrar);
}

DesktopMultiWindowPlugin::~DesktopMultiWindowPlugin() {
   MultiWindowManager::Instance()->RemoveWindow(window_->GetWindowId());
}

void DesktopMultiWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Check if this is a window-specific method (starts with "window_")
  const auto& method = method_call.method_name();
  if (method.rfind("window_", 0) == 0) {
    auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto window_id = std::get<std::string>(
        arguments->at(flutter::EncodableValue("windowId")));

    auto window = MultiWindowManager::Instance()->GetWindow(window_id);
    if (!window) {
      result->Error("-1", "failed to find target window: " + window_id);
      return;
    }

    window->HandleWindowMethod(method, arguments, std::move(result));
    return;
  }

  if (method == "createWindow") {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto window_id = MultiWindowManager::Instance()->Create(args);
    result->Success(flutter::EncodableValue(window_id));
    return;
  } else if (method == "getWindowDefinition") {
    flutter::EncodableMap definition;
    definition[flutter::EncodableValue("windowId")] =
        flutter::EncodableValue(window_->GetWindowId());
    definition[flutter::EncodableValue("windowArgument")] =
        flutter::EncodableValue(window_->GetWindowArgument());
    result->Success(flutter::EncodableValue(definition));
    return;
  } else if (method == "getAllWindows") {
    auto windows = MultiWindowManager::Instance()->GetAllWindows();
    result->Success(flutter::EncodableValue(windows));
    return;
  }

  result->NotImplemented();
}

}  // namespace

void DesktopMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  // Attach MainWindow
  auto hwnd = FlutterDesktopViewGetHWND(
      FlutterDesktopPluginRegistrarGetView(registrar));
  MultiWindowManager::Instance()->AttachFlutterMainWindow(
      GetAncestor(hwnd, GA_ROOT), registrar);
}

void InternalMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar,
    FlutterWindowWrapper* window) {
  auto plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  auto plugin =
      std::make_unique<DesktopMultiWindowPlugin>(window, plugin_registrar);
  plugin_registrar->AddPlugin(std::move(plugin));
}

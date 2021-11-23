#include "include/desktop_lifecycle/desktop_lifecycle_plugin.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

namespace {

class DesktopLifecyclePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit DesktopLifecyclePlugin(
      flutter::PluginRegistrarWindows *registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  ~DesktopLifecyclePlugin() override;

 private:

  flutter::PluginRegistrarWindows *registrar_;

  int proc_id_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::optional<HRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  void DispatchApplicationState(bool active) {
    channel_->InvokeMethod(
        "onApplicationFocusChanged",
        std::make_unique<flutter::EncodableValue>(active));
  }

};

// static
void DesktopLifecyclePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "desktop_lifecycle",
      &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd = nullptr;
  if (registrar->GetView()) {
    hwnd = registrar->GetView()->GetNativeWindow();
  }
  if (!hwnd) {
    std::cerr << "DesktopLifecyclePlugin: no flutter window." << std::endl;
    return;
  }

  auto plugin = std::make_unique<DesktopLifecyclePlugin>(registrar, std::move(channel));
  registrar->AddPlugin(std::move(plugin));
}

DesktopLifecyclePlugin::DesktopLifecyclePlugin(
    flutter::PluginRegistrarWindows *registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel
) : registrar_(registrar), channel_(std::move(channel)) {
  proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return this->HandleWindowProc(hwnd, message, wparam, lparam);
      });
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    this->HandleMethodCall(call, std::move(result));
  });
}

DesktopLifecyclePlugin::~DesktopLifecyclePlugin() {
  registrar_->UnregisterTopLevelWindowProcDelegate(proc_id_);
}

std::optional<HRESULT> DesktopLifecyclePlugin::HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ACTIVATE) {
    if (LOWORD(wparam) == WA_INACTIVE) {
      DispatchApplicationState(false);
    } else {
      // the window being activated
      DispatchApplicationState(true);
    }
  }
  // return null to allow the default window proc to handle the message
  return std::nullopt;
}

void DesktopLifecyclePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "init") {
    DispatchApplicationState(true);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void DesktopLifecyclePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  DesktopLifecyclePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

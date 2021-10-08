#include "include/desktop_lifecycle/desktop_lifecycle_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

namespace {

using ChannelPtr =
    std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>;

HHOOK h_event_hook;

HINSTANCE h_instance;

ChannelPtr plugin_channel;

void DispatchApplicatinState(bool active) {
  if (!plugin_channel) {
    std::cerr << "dispatch application state failed, plugin channel is null."
              << std::endl;
    return;
  }
  plugin_channel->InvokeMethod(
      "onApplicationFocusChanged",
      std::make_unique<flutter::EncodableValue>(active));
}

// static
LRESULT CALLBACK CbtProc(int code, WPARAM w_param, LPARAM l_param) {
  if (code >= 0) {
    CWPSTRUCT *cwp = (CWPSTRUCT *)l_param;
    if (cwp->message == WM_ACTIVATE) {
      if (LOWORD(cwp->wParam) == WA_INACTIVE) {
        DispatchApplicatinState(false);
      } else {
        // the window being activated
        DispatchApplicatinState(true);
      }
    }
  }

  return CallNextHookEx(h_event_hook, code, w_param, l_param);
}

class DesktopLifecyclePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit DesktopLifecyclePlugin(HWND hwnd);

  virtual ~DesktopLifecyclePlugin();

 private:
  HWND hwnd_;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

// static
void DesktopLifecyclePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "desktop_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());

  plugin_channel = channel;

  HWND hwnd;
  if (registrar->GetView()) {
    hwnd = registrar->GetView()->GetNativeWindow();
  }

  auto plugin = std::make_unique<DesktopLifecyclePlugin>(hwnd);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopLifecyclePlugin::DesktopLifecyclePlugin(HWND hwnd) : hwnd_(hwnd) {
  if (hwnd_) {
    h_event_hook = SetWindowsHookEx(WH_CALLWNDPROC, CbtProc, h_instance, 0);
    if (!h_event_hook) {
      std::cout << "SetWindowsHookEx failed:  " << GetLastError() << std::endl;
    }
  }
}

DesktopLifecyclePlugin::~DesktopLifecyclePlugin() {
  if (h_event_hook) {
    UnhookWindowsHookEx(h_event_hook);
  }
}

void DesktopLifecyclePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("init") == 0) {
    if (hwnd_) {
      DispatchApplicatinState(true);
    } else {
      DispatchApplicatinState(false);
    }
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

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call,
                      LPVOID lpReserved) {
  h_instance = reinterpret_cast<HINSTANCE>(hModule);
  return TRUE;
}

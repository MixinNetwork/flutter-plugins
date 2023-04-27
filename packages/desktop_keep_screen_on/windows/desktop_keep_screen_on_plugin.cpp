#include "desktop_keep_screen_on_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace desktop_keep_screen_on {

// static
void DesktopKeepScreenOnPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "one.mixin/desktop_keep_screen_on",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopKeepScreenOnPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopKeepScreenOnPlugin::DesktopKeepScreenOnPlugin() {}

DesktopKeepScreenOnPlugin::~DesktopKeepScreenOnPlugin() {}

void DesktopKeepScreenOnPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("setPreventSleep") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto prevent_sleep = std::get<bool>(arguments[flutter::EncodableValue("preventSleep")]);
    if (prevent_sleep) {
      SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
    } else {
      SetThreadExecutionState(ES_CONTINUOUS);
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace desktop_keep_screen_on

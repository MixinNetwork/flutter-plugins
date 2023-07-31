#ifndef FLUTTER_PLUGIN_DESKTOP_KEEP_SCREEN_ON_PLUGIN_H_
#define FLUTTER_PLUGIN_DESKTOP_KEEP_SCREEN_ON_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace desktop_keep_screen_on {

class DesktopKeepScreenOnPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DesktopKeepScreenOnPlugin();

  virtual ~DesktopKeepScreenOnPlugin();

  // Disallow copy and assign.
  DesktopKeepScreenOnPlugin(const DesktopKeepScreenOnPlugin&) = delete;
  DesktopKeepScreenOnPlugin& operator=(const DesktopKeepScreenOnPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace desktop_keep_screen_on

#endif  // FLUTTER_PLUGIN_DESKTOP_KEEP_SCREEN_ON_PLUGIN_H_

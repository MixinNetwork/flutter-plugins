#include "include/desktop_keep_screen_on/desktop_keep_screen_on_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "desktop_keep_screen_on_plugin.h"

void DesktopKeepScreenOnPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  desktop_keep_screen_on::DesktopKeepScreenOnPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

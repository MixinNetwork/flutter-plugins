#include "include/desktop_webview_window/desktop_webview_window_plugin.h"

#include "web_view_window_plugin.h"

void DesktopWebviewWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WebviewWindowPlugin::RegisterWithRegistrar(registrar);
}

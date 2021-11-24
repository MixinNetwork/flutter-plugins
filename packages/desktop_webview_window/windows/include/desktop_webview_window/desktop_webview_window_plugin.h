#ifndef FLUTTER_PLUGIN_WEBVIEW_WINDOW_PLUGIN_H_
#define FLUTTER_PLUGIN_WEBVIEW_WINDOW_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void DesktopWebviewWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

class WebviewWindowAdapter {
 public:
  virtual std::unique_ptr<flutter::FlutterViewController> CreateViewController(
      int width,
      int height,
      const flutter::DartProject &project
  ) {
    return std::make_unique<flutter::FlutterViewController>(width, height, project);
  }

  virtual std::optional<LRESULT> HandleTopLevelWindowProc(
      const std::unique_ptr<flutter::FlutterViewController> &flutter_view_controller,
      HWND hwnd,
      UINT message,
      WPARAM wparam,
      LPARAM lparam
  ) {
    return flutter_view_controller->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
  }

  virtual void ReloadSystemFonts(const std::unique_ptr<flutter::FlutterViewController> &flutter_view_controller) {
    flutter_view_controller->engine()->ReloadSystemFonts();
  }

};

FLUTTER_PLUGIN_EXPORT void SetFlutterViewControllerFactory(std::unique_ptr<WebviewWindowAdapter> adapter);

#endif  // FLUTTER_PLUGIN_WEBVIEW_WINDOW_PLUGIN_H_

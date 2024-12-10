#ifndef FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_
#define FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_

#include <flutter_plugin_registrar.h>
#include <functional>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void DesktopMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

// flutter_view_controller: pointer to the flutter::FlutterViewController

using WindowCreatedCallback = std::function<void(
        void* flutter_view_controller,
        FlutterDesktopTextureRegistrarRef texture_registrar,
        int64_t windowId)>;
FLUTTER_PLUGIN_EXPORT void DesktopMultiWindowSetWindowCreatedCallback(WindowCreatedCallback callback);

using WindowClosedCallback = std::function<void(int64_t)>;
FLUTTER_PLUGIN_EXPORT void DesktopMultiWindowSetWindowClosedCallback(WindowClosedCallback callback);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_

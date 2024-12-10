#ifndef FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_
#define FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _DesktopMultiWindowPlugin DesktopMultiWindowPlugin;
typedef struct {
  GObjectClass parent_class;
} DesktopMultiWindowPluginClass;

FLUTTER_PLUGIN_EXPORT GType desktop_multi_window_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void desktop_multi_window_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

typedef void (*WindowCreatedCallback)(FlPluginRegistry *registry);


using WindowCreatedCallback = std::function<void(
        FlPluginRegistry *registry,
        FlutterDesktopTextureRegistrarRef texture_registrar,
        int64_t windowId)>;

FLUTTER_PLUGIN_EXPORT void desktop_multi_window_plugin_set_window_created_callback(
    WindowCreatedCallback callback);

using WindowClosedCallback = std::function<void(int64_t)>;
FLUTTER_PLUGIN_EXPORT void desktop_multi_window_plugin_set_window_closed_callback(
    WindowClosedCallback);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_DESKTOP_MULTI_WINDOW_PLUGIN_H_

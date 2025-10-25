#ifndef DESKTOP_MULTI_WINDOW_LINUX_WINDOW_CHANNEL_PLUGIN_H_
#define DESKTOP_MULTI_WINDOW_LINUX_WINDOW_CHANNEL_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

G_DECLARE_FINAL_TYPE(WindowChannelPlugin,
                     window_channel_plugin,
                     WINDOW,
                     CHANNEL_PLUGIN,
                     GObject)

void window_channel_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // DESKTOP_MULTI_WINDOW_LINUX_WINDOW_CHANNEL_PLUGIN_H_

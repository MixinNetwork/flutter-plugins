#ifndef FLUTTER_PLUGIN_FTS5_SIMPLE_PLUGIN_H_
#define FLUTTER_PLUGIN_FTS5_SIMPLE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void fts5_simple_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FTS5_SIMPLE_PLUGIN_H_

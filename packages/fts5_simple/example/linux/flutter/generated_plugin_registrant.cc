//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <fts5_simple/fts5_simple_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) fts5_simple_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Fts5SimplePlugin");
  fts5_simple_plugin_register_with_registrar(fts5_simple_registrar);
}

//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <pasteboard/pasteboard_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) pasteboard_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PasteboardPlugin");
  pasteboard_plugin_register_with_registrar(pasteboard_registrar);
}

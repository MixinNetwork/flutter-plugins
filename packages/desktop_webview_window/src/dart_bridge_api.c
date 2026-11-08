#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#endif
#include "dart_bridge_api.h"
#include "vendor/dart_api_dl.h"
#include "vendor/dart_version.h"
#include "vendor/internal/dart_api_dl_impl.h"
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

#include <string.h>

// Resolve only the three SDK API DL functions used by this bridge. This follows
// the vendored SDK loader's version check and function table lookup, while
// keeping every function pointer private when SwiftPM links plugins statically.
static Dart_PostCObject_Type post_object;
static Dart_GetMainPortId_Type main_port;
static Dart_GetCurrentThreadOwnsIsolate_Type owns_isolate;

intptr_t dww_dart_initialize(void* api) {
  if (!api) return -1;
  const DartApi* table = (const DartApi*)api;
  if (table->major != DART_API_DL_MAJOR_VERSION) return -1;
  for (const DartApiEntry* entry = table->functions; entry->name; ++entry) {
    if (strcmp(entry->name, "Dart_PostCObject") == 0)
      post_object = (Dart_PostCObject_Type)entry->function;
    else if (strcmp(entry->name, "Dart_GetMainPortId") == 0)
      main_port = (Dart_GetMainPortId_Type)entry->function;
    else if (strcmp(entry->name, "Dart_GetCurrentThreadOwnsIsolate") == 0)
      owns_isolate = (Dart_GetCurrentThreadOwnsIsolate_Type)entry->function;
  }
  return post_object && main_port && owns_isolate ? 0 : -1;
}

bool dww_dart_owns_isolate(Dart_Port port) { return owns_isolate(port); }
Dart_Port dww_dart_main_port(void) { return main_port(); }
bool dww_dart_post(Dart_Port port, Dart_CObject* message) {
  return post_object(port, message);
}

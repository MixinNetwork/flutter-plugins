#pragma once

#include "vendor/dart_native_api.h"

#if defined(_WIN32)
#define DWW_PRIVATE
#else
#define DWW_PRIVATE __attribute__((visibility("hidden")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Keep the SDK loader's global variables private to this plugin, including
// when SwiftPM links several FFI plugins statically into one application.
DWW_PRIVATE intptr_t dww_dart_initialize(void* api);
DWW_PRIVATE bool dww_dart_owns_isolate(Dart_Port port);
DWW_PRIVATE Dart_Port dww_dart_main_port(void);
DWW_PRIVATE bool dww_dart_post(Dart_Port port, Dart_CObject* message);

#ifdef __cplusplus
}
#endif

#pragma once

#include "vendor/dart_native_api.h"

#ifdef __cplusplus
extern "C" {
#endif

// Keep the SDK loader's global variables private to this plugin, including
// when SwiftPM links several FFI plugins statically into one application.
intptr_t dd_dart_initialize(void* api);
bool dd_dart_owns_isolate(Dart_Port port);
Dart_Port dd_dart_main_port(void);
bool dd_dart_post(Dart_Port port, Dart_CObject* message);

#ifdef __cplusplus
}
#endif

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int64_t context;
  int64_t generation;
  int64_t request;
  int64_t view;
  int64_t session;
  int32_t phase;
  int32_t length;
  double x;
  double y;
  const char* payload;
} DDRequest;

typedef struct {
  int64_t generation;
  int64_t request;
  int64_t target;
} DDDecision;

typedef int64_t (*DDDecide)(const DDRequest* request);

typedef struct {
  int64_t context;
  intptr_t register_callback;
  intptr_t complete;
  intptr_t unregister_callback;
} DDBridgeFunctions;

// The bridge lives here so SwiftPM can compile it as a separate C++ target.
// Windows compiles these same sources through its CMake target.
DDBridgeFunctions dd_bridge_create(void);
void dd_bridge_destroy(int64_t context);
int64_t dd_bridge_register(int64_t context, void* api, int64_t port,
                           DDDecide decide, int32_t merged, int64_t view);
int32_t dd_bridge_complete(int64_t context, int64_t generation,
                          int64_t request, int64_t target);
void dd_bridge_unregister(int64_t context, int64_t generation);
int64_t dd_bridge_generation(int64_t context);

// phases: 0 = enter, 1 = update, 2 = final acceptance before materialization.
DDDecision dd_bridge_decide(int64_t context, int64_t session, int32_t phase,
                            double x, double y, const char* payload);
void dd_bridge_cancel(int64_t context, int64_t generation, int64_t request);

#ifdef __cplusplus
}
#endif

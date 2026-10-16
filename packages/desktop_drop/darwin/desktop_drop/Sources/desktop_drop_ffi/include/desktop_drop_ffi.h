// Generated from src/desktop_drop_ffi.h. Do not edit.
// Regenerate with: dart run tool/ffigen.dart

#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define DD_EXPORT __declspec(dllexport)
#else
#define DD_EXPORT __attribute__((visibility("default"), used))
#endif

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
  const uint8_t* payload;
} DDRequest;

typedef struct {
  int64_t generation;
  int64_t request;
  // Positive = selected target, 0 = reject, -1 = resend the session offer.
  int64_t target;
  // 0 = reject, 1 = copy, 2 = move, 3 = link.
  int32_t operation;
} DDDecision;

// Synchronous callback: fill target/operation without retaining either pointer.
typedef void (*DDDecide)(const DDRequest* request, DDDecision* decision);

// Byte buffers are borrowed for the duration of each call. Receivers must copy
// before dispatching to another thread. Replies are paired by request ID.
typedef void (*DDInvoke)(void* user, int64_t context, int64_t epoch,
                         int64_t request, const uint8_t* bytes, int32_t length);
typedef void (*DDReply)(void* user, const uint8_t* bytes, int32_t length);
typedef int32_t (*DDMatch)(void* user, int64_t engine);
int64_t dd_rpc_create(int64_t engine, DDInvoke invoke, void* user, DDMatch match);
void dd_rpc_destroy(int64_t context);
DD_EXPORT int64_t dd_rpc_open(int64_t engine, void* api, int64_t port);
DD_EXPORT void dd_rpc_call(int64_t context, int64_t request,
                           const uint8_t* bytes, int32_t length);
void dd_rpc_reply(int64_t context, int64_t epoch, int64_t request,
                   const uint8_t* bytes, int32_t length);
int64_t dd_rpc_send(int64_t context, const uint8_t* bytes, int32_t length,
                     DDReply reply, void* user);
DD_EXPORT void dd_rpc_complete(int64_t context, int64_t request,
                               const uint8_t* bytes, int32_t length);
DD_EXPORT void dd_rpc_cancel(int64_t context, int64_t request);
DD_EXPORT uint8_t* dd_alloc(int32_t length);
DD_EXPORT void dd_free(uint8_t* bytes);

// Shared by all native platforms. Darwin compiles these sources through
// forwarders in its Swift Package Manager / CocoaPods target.
int64_t dd_bridge_create(void);
void dd_bridge_destroy(int64_t context);
DD_EXPORT int64_t dd_bridge_register(int64_t context, void* api, int64_t port,
                           DDDecide decide, int32_t merged, int64_t view);
DD_EXPORT int32_t dd_bridge_complete(int64_t context, int64_t generation,
                          int64_t request, int64_t target, int32_t operation);
DD_EXPORT void dd_bridge_unregister(int64_t context, int64_t generation);
int64_t dd_bridge_generation(int64_t context);

// phases: 0 = enter, 1 = update, 2 = final acceptance before materialization.
DDDecision dd_bridge_decide(int64_t context, int64_t session, int32_t phase,
                            double x, double y, const uint8_t* payload, int32_t length);
void dd_bridge_cancel(int64_t context, int64_t generation, int64_t request);

#ifdef __cplusplus
}
#endif

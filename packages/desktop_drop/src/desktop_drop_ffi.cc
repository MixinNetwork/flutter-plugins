#include "desktop_drop_ffi.h"
#include "dart_bridge_api.h"

#include <atomic>
#include <cstdlib>
#include <chrono>
#include <condition_variable>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
struct Pending {
  std::mutex mutex;
  std::condition_variable ready;
  bool finished = false;
  DDDecision decision{};
};

struct Context {
  std::mutex mutex;
  int64_t generation = 0;
  int64_t view = 0;
  Dart_Port port = 0;
  Dart_Port root_port = 0;
  DDDecide decide = nullptr;
  bool merged = false;
  std::unordered_map<int64_t, std::shared_ptr<Pending>> pending;
};

std::mutex registry_mutex;
std::unordered_map<int64_t, std::shared_ptr<Context>> registry;
std::atomic<int64_t> next_context{1};
std::atomic<int64_t> next_request{1};
std::once_flag initialize_api;
bool api_ready = false;

std::shared_ptr<Context> Lookup(int64_t handle) {
  std::lock_guard<std::mutex> lock(registry_mutex);
  const auto found = registry.find(handle);
  return found == registry.end() ? nullptr : found->second;
}

void Finish(const std::shared_ptr<Pending>& pending, int64_t target, int32_t operation = 0) {
  {
    std::lock_guard<std::mutex> lock(pending->mutex);
    if (pending->finished) return;
    pending->finished = true;
    const bool accepted = target > 0 && operation >= 1 && operation <= 3;
    // -1 asks the adapter to resend content missing from Dart's session cache.
    pending->decision.target = accepted ? target : target == -1 ? -1 : 0;
    pending->decision.operation = accepted ? operation : 0;
  }
  pending->ready.notify_all();
}

void Reset(const std::shared_ptr<Context>& context, int64_t generation) {
  std::vector<std::shared_ptr<Pending>> pending;
  {
    std::lock_guard<std::mutex> lock(context->mutex);
    if (generation && context->generation != generation) return;
    context->port = 0;
    context->root_port = 0;
    context->decide = nullptr;
    for (const auto& entry : context->pending) pending.push_back(entry.second);
    context->pending.clear();
  }
  for (const auto& request : pending) Finish(request, 0);
}

bool Post(Dart_Port port, const DDRequest& request) {
  // Dart_PostCObject copies these values before returning. No native request
  // pointer escapes into the isolate, including when a reply arrives late.
  Dart_CObject values[9]{};
  const int64_t integers[] = {request.context, request.generation,
                             request.request, request.view, request.session,
                             request.phase};
  for (int i = 0; i < 6; ++i) {
    values[i].type = Dart_CObject_kInt64;
    values[i].value.as_int64 = integers[i];
  }
  values[6].type = Dart_CObject_kDouble;
  values[6].value.as_double = request.x;
  values[7].type = Dart_CObject_kDouble;
  values[7].value.as_double = request.y;
  values[8].type = Dart_CObject_kTypedData;
  values[8].value.as_typed_data.type = Dart_TypedData_kUint8;
  values[8].value.as_typed_data.length = request.length;
  values[8].value.as_typed_data.values = const_cast<uint8_t*>(request.payload);
  Dart_CObject* pointers[9];
  for (int i = 0; i < 9; ++i) pointers[i] = &values[i];
  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = 9;
  message.value.as_array.values = pointers;
  return dd_dart_post(port, &message);
}

DDDecision Request(int64_t handle, int64_t session, int32_t phase, double x,
                   double y, const uint8_t* payload, int32_t length) {
  const auto context = Lookup(handle);
  DDDecision rejected{};
  if (!context || !payload) {
    return rejected;
  }
  if (length < 0) return rejected;
  const std::vector<uint8_t> data(payload, payload + length);
  DDRequest request{};
  Dart_Port port;
  Dart_Port root_port;
  DDDecide decide;
  bool merged;
  auto pending = std::make_shared<Pending>();
  {
    std::lock_guard<std::mutex> lock(context->mutex);
    request = {handle, context->generation, next_request.fetch_add(1),
               context->view, session, phase, length,
               x, y, data.data()};
    port = context->port;
    root_port = context->root_port;
    decide = context->decide;
    merged = context->merged;
    pending->decision = {request.generation, request.request, 0, 0};
    if (port && !merged) context->pending.emplace(request.request, pending);
  }
  if (!port) {
    Finish(pending, 0);
  } else if (merged) {
    // A closed/restarted isolate must never be called through its old FFI
    // trampoline. Ownership is checked before touching the function pointer.
    const bool owns = decide && root_port &&
                      dd_dart_owns_isolate(root_port);
    DDDecision response{};
    if (owns) decide(&request, &response);
    Finish(pending, response.target, response.operation);
  } else if (!Post(port, request)) {
    dd_bridge_cancel(handle, request.generation, request.request);
  }
  std::unique_lock<std::mutex> lock(pending->mutex);
  if (!pending->ready.wait_for(lock, std::chrono::milliseconds(100),
                               [&] { return pending->finished; })) {
    pending->finished = true;
    pending->decision.target = 0;
    pending->decision.operation = 0;
    lock.unlock();
    dd_bridge_cancel(handle, request.generation, request.request);
    lock.lock();
  }
  return pending->decision;
}
}  // namespace

int64_t dd_bridge_create() {
  const int64_t handle = next_context.fetch_add(1);
  {
    std::lock_guard<std::mutex> lock(registry_mutex);
    registry.emplace(handle, std::make_shared<Context>());
  }
  return handle;
}

void dd_bridge_destroy(int64_t handle) {
  std::shared_ptr<Context> context;
  {
    std::lock_guard<std::mutex> lock(registry_mutex);
    const auto found = registry.find(handle);
    if (found == registry.end()) return;
    context = found->second;
    registry.erase(found);
  }
  Reset(context, 0);
}

int64_t dd_bridge_register(int64_t handle, void* api, int64_t port,
                           DDDecide decide, int32_t merged, int64_t view) {
  std::call_once(initialize_api, [api] {
    api_ready = dd_dart_initialize(api) == 0;
  });
  const auto context = Lookup(handle);
  if (!api_ready || !context || !decide || !port) return 0;
  Reset(context, 0);
  std::lock_guard<std::mutex> lock(context->mutex);
  context->generation++;
  context->view = view;
  context->port = port;
  context->root_port = dd_dart_main_port();
  context->decide = decide;
  context->merged = merged != 0;
  return context->generation;
}

int32_t dd_bridge_complete(int64_t handle, int64_t generation, int64_t request,
                          int64_t target, int32_t operation) {
  const auto context = Lookup(handle);
  if (!context) return 0;
  std::shared_ptr<Pending> pending;
  {
    std::lock_guard<std::mutex> lock(context->mutex);
    if (context->generation != generation) return 0;
    const auto found = context->pending.find(request);
    if (found == context->pending.end()) return 0;
    pending = found->second;
    context->pending.erase(found);
  }
  Finish(pending, target, operation);
  return 1;
}

void dd_bridge_unregister(int64_t handle, int64_t generation) {
  const auto context = Lookup(handle);
  if (context) Reset(context, generation);
}

int64_t dd_bridge_generation(int64_t handle) {
  const auto context = Lookup(handle);
  if (!context) return 0;
  std::lock_guard<std::mutex> lock(context->mutex);
  return context->port ? context->generation : 0;
}

DDDecision dd_bridge_decide(int64_t handle, int64_t session, int32_t phase,
                            double x, double y, const uint8_t* payload, int32_t length) {
  return Request(handle, session, phase, x, y, payload, length);
}

void dd_bridge_cancel(int64_t handle, int64_t generation, int64_t request) {
  dd_bridge_complete(handle, generation, request, 0, 0);
}

namespace {
struct Reply { DDReply callback; void* user; };
struct Rpc {
  int64_t engine;
  DDInvoke invoke;
  void* user;
  DDMatch match;
  int64_t epoch = 0;
  Dart_Port port = 0;
  std::unordered_map<int64_t, Reply> replies;
};
std::recursive_mutex rpc_mutex;
std::unordered_map<int64_t, Rpc> rpcs;
bool PostBytes(Dart_Port port, int64_t kind, int64_t request, const uint8_t* bytes, int32_t length) {
  if (!port || length < 0) return false;
  Dart_CObject values[3]{};
  values[0].type = values[1].type = Dart_CObject_kInt64;
  values[0].value.as_int64 = kind;
  values[1].value.as_int64 = request;
  values[2].type = Dart_CObject_kTypedData;
  values[2].value.as_typed_data.type = Dart_TypedData_kUint8;
  values[2].value.as_typed_data.length = length;
  values[2].value.as_typed_data.values = const_cast<uint8_t*>(bytes);
  Dart_CObject* pointers[] = {&values[0], &values[1], &values[2]};
  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = 3;
  message.value.as_array.values = pointers;
  return dd_dart_post(port, &message);
}
void ResetRpc(Rpc& rpc) {
  if (rpc.port) PostBytes(rpc.port, 2, 0, nullptr, 0);
  rpc.port = 0;
  ++rpc.epoch;
  auto replies = std::move(rpc.replies);
  rpc.replies.clear();
  for (const auto& entry : replies) entry.second.callback(entry.second.user, nullptr, 0);
}
}  // namespace
int64_t dd_rpc_create(int64_t engine, DDInvoke invoke, void* user, DDMatch match) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  const auto handle = next_context.fetch_add(1);
  rpcs.emplace(handle, Rpc{engine, invoke, user, match, 0, 0, {}});
  return handle;
}
void dd_rpc_destroy(int64_t handle) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  auto found = rpcs.find(handle);
  if (found == rpcs.end()) return;
  auto rpc = std::move(found->second);
  rpcs.erase(found);
  ResetRpc(rpc);
}
int64_t dd_rpc_open(int64_t engine, void* api, int64_t port) {
  std::call_once(initialize_api, [api] { api_ready = dd_dart_initialize(api) == 0; });
  if (!api_ready || !port) return 0;
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  for (auto& entry : rpcs) {
    auto& rpc = entry.second;
    if (rpc.engine != engine && (!rpc.match || !rpc.match(rpc.user, engine))) continue;
    ResetRpc(rpc);
    rpc.port = port;
    return entry.first;
  }
  return 0;
}
void dd_rpc_call(int64_t handle, int64_t request, const uint8_t* bytes, int32_t length) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  auto found = rpcs.find(handle);
  if (found == rpcs.end() || !found->second.port || length < 0) return;
  auto& rpc = found->second;
  rpc.invoke(rpc.user, handle, rpc.epoch, request, bytes, length);
}
void dd_rpc_reply(int64_t handle, int64_t epoch, int64_t request, const uint8_t* bytes, int32_t length) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  auto found = rpcs.find(handle);
  if (found != rpcs.end() && found->second.epoch == epoch)
    PostBytes(found->second.port, 1, request, bytes, length);
}
int64_t dd_rpc_send(int64_t handle, const uint8_t* bytes, int32_t length, DDReply reply, void* user) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  auto found = rpcs.find(handle);
  const auto request = reply ? next_request.fetch_add(1) : 0;
  if (found != rpcs.end()) {
    if (reply) found->second.replies.emplace(request, Reply{reply, user});
    if (PostBytes(found->second.port, 0, request, bytes, length)) return request;
    if (reply) found->second.replies.erase(request);
  }
  if (reply) reply(user, nullptr, 0);
  return 0;
}
void dd_rpc_complete(int64_t handle, int64_t request, const uint8_t* bytes, int32_t length) {
  std::lock_guard<std::recursive_mutex> lock(rpc_mutex);
  auto found = rpcs.find(handle);
  if (found == rpcs.end()) return;
  auto pending = found->second.replies.find(request);
  if (pending == found->second.replies.end()) return;
  const auto reply = pending->second;
  found->second.replies.erase(pending);
  reply.callback(reply.user, bytes, length);
}
void dd_rpc_cancel(int64_t handle, int64_t request) { dd_rpc_complete(handle, request, nullptr, 0); }
uint8_t* dd_alloc(int32_t length) { return length > 0 ? static_cast<uint8_t*>(std::malloc(length)) : nullptr; }
void dd_free(uint8_t* bytes) { std::free(bytes); }

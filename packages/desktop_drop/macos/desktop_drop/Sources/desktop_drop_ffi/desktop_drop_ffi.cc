#include "include/desktop_drop_ffi.h"
#include "dart_bridge_api.h"

#include <atomic>
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

void Finish(const std::shared_ptr<Pending>& pending, int64_t target) {
  {
    std::lock_guard<std::mutex> lock(pending->mutex);
    if (pending->finished) return;
    pending->finished = true;
    pending->decision.target = target;
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
  values[8].type = Dart_CObject_kString;
  values[8].value.as_string = const_cast<char*>(request.payload);
  Dart_CObject* pointers[9];
  for (int i = 0; i < 9; ++i) pointers[i] = &values[i];
  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = 9;
  message.value.as_array.values = pointers;
  return dd_dart_post(port, &message);
}

DDDecision Request(int64_t handle, int64_t session, int32_t phase, double x,
                   double y, const char* payload) {
  const auto context = Lookup(handle);
  DDDecision rejected{};
  if (!context || !payload) {
    return rejected;
  }
  const std::string json(payload);
  if (json.size() > static_cast<size_t>(std::numeric_limits<int32_t>::max())) {
    return rejected;
  }
  DDRequest request{};
  Dart_Port port;
  Dart_Port root_port;
  DDDecide decide;
  bool merged;
  auto pending = std::make_shared<Pending>();
  {
    std::lock_guard<std::mutex> lock(context->mutex);
    request = {handle, context->generation, next_request.fetch_add(1),
               context->view, session, phase, static_cast<int32_t>(json.size()),
               x, y, json.c_str()};
    port = context->port;
    root_port = context->root_port;
    decide = context->decide;
    merged = context->merged;
    pending->decision = {request.generation, request.request, 0};
    if (port && !merged) context->pending.emplace(request.request, pending);
  }
  if (!port) {
    Finish(pending, 0);
  } else if (merged) {
    // A closed/restarted isolate must never be called through its old FFI
    // trampoline. Ownership is checked before touching the function pointer.
    const bool owns = decide && root_port &&
                      dd_dart_owns_isolate(root_port);
    Finish(pending, owns ? decide(&request) : 0);
  } else if (!Post(port, request)) {
    dd_bridge_cancel(handle, request.generation, request.request);
  }
  std::unique_lock<std::mutex> lock(pending->mutex);
  if (!pending->ready.wait_for(lock, std::chrono::milliseconds(100),
                               [&] { return pending->finished; })) {
    pending->finished = true;
    pending->decision.target = 0;
    lock.unlock();
    dd_bridge_cancel(handle, request.generation, request.request);
    lock.lock();
  }
  return pending->decision;
}
}  // namespace

DDBridgeFunctions dd_bridge_create() {
  const int64_t handle = next_context.fetch_add(1);
  {
    std::lock_guard<std::mutex> lock(registry_mutex);
    registry.emplace(handle, std::make_shared<Context>());
  }
  return {handle, reinterpret_cast<intptr_t>(dd_bridge_register),
          reinterpret_cast<intptr_t>(dd_bridge_complete),
          reinterpret_cast<intptr_t>(dd_bridge_unregister)};
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
                          int64_t target) {
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
  Finish(pending, target > 0 ? target : 0);
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
                            double x, double y, const char* payload) {
  return Request(handle, session, phase, x, y, payload);
}

void dd_bridge_cancel(int64_t handle, int64_t generation, int64_t request) {
  dd_bridge_complete(handle, generation, request, 0);
}

#include "navigation_decider.h"

#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "dart_bridge_api.h"

namespace {

// How long the platform thread waits for an isolate on its own UI thread.
constexpr auto kReplyTimeout = std::chrono::milliseconds(500);

struct Pending {
  std::mutex mutex;
  std::condition_variable ready;
  bool finished = false;
  bool allow = true;
};

struct Listener {
  std::mutex mutex;
  int64_t generation = 0;
  int64_t next_request = 1;
  Dart_Port port = 0;
  Dart_Port root_port = 0;
  DWWNavigationDecide decide = nullptr;
  bool merged = false;
  std::unordered_map<int64_t, std::shared_ptr<Pending>> pending;
};

Listener& Current() {
  static auto* listener = new Listener();
  return *listener;
}

std::once_flag initialize_api;
bool api_ready = false;

void Finish(const std::shared_ptr<Pending>& pending, bool allow) {
  {
    std::lock_guard<std::mutex> lock(pending->mutex);
    if (pending->finished) return;
    pending->finished = true;
    pending->allow = allow;
  }
  pending->ready.notify_all();
}

std::shared_ptr<Pending> Take(int64_t generation, int64_t request) {
  auto& listener = Current();
  std::lock_guard<std::mutex> lock(listener.mutex);
  if (listener.generation != generation) return nullptr;
  const auto found = listener.pending.find(request);
  if (found == listener.pending.end()) return nullptr;
  auto pending = found->second;
  listener.pending.erase(found);
  return pending;
}

// Clears the listener of |generation|, or any listener when it is 0, and
// allows its waiting navigations.
void Reset(int64_t generation) {
  auto& listener = Current();
  std::vector<std::shared_ptr<Pending>> pending;
  {
    std::lock_guard<std::mutex> lock(listener.mutex);
    if (generation && listener.generation != generation) return;
    listener.port = 0;
    listener.root_port = 0;
    listener.decide = nullptr;
    for (const auto& entry : listener.pending) pending.push_back(entry.second);
    listener.pending.clear();
  }
  for (const auto& request : pending) Finish(request, true);
}

bool Post(Dart_Port port, int64_t generation, int64_t request,
          int64_t browser, const std::string& url) {
  // Dart_PostCObject copies the values before returning.
  Dart_CObject values[4]{};
  const int64_t integers[] = {generation, request, browser};
  for (int i = 0; i < 3; ++i) {
    values[i].type = Dart_CObject_kInt64;
    values[i].value.as_int64 = integers[i];
  }
  values[3].type = Dart_CObject_kString;
  values[3].value.as_string = const_cast<char*>(url.c_str());
  Dart_CObject* pointers[4];
  for (int i = 0; i < 4; ++i) pointers[i] = &values[i];
  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = 4;
  message.value.as_array.values = pointers;
  return dww_dart_post(port, &message);
}

}  // namespace

namespace dww {

bool DecideNavigation(int64_t browser, const std::string& url) {
  auto& listener = Current();
  auto pending = std::make_shared<Pending>();
  int64_t generation;
  int64_t request;
  Dart_Port port;
  Dart_Port root_port;
  DWWNavigationDecide decide;
  bool merged;
  {
    std::lock_guard<std::mutex> lock(listener.mutex);
    generation = listener.generation;
    request = listener.next_request++;
    port = listener.port;
    root_port = listener.root_port;
    decide = listener.decide;
    merged = listener.merged;
    if (port && !merged) listener.pending.emplace(request, pending);
  }
  if (!port) return true;
  if (merged) {
    // A restarted isolate must never be called through its old trampoline.
    if (!decide || !root_port || !dww_dart_owns_isolate(root_port)) return true;
    return decide(browser, reinterpret_cast<const uint8_t*>(url.data()),
                  static_cast<int32_t>(url.size())) != 0;
  }
  if (!Post(port, generation, request, browser, url)) {
    Take(generation, request);
    return true;
  }
  std::unique_lock<std::mutex> lock(pending->mutex);
  if (!pending->ready.wait_for(lock, kReplyTimeout,
                               [&] { return pending->finished; })) {
    pending->finished = true;
    lock.unlock();
    Take(generation, request);
    return true;
  }
  return pending->allow;
}

}  // namespace dww

int64_t dww_navigation_register(void* api, int64_t port,
                                DWWNavigationDecide decide, int32_t merged) {
  std::call_once(initialize_api,
                 [api] { api_ready = dww_dart_initialize(api) == 0; });
  if (!api_ready || !decide || !port) return 0;
  Reset(0);
  auto& listener = Current();
  std::lock_guard<std::mutex> lock(listener.mutex);
  listener.generation++;
  listener.port = port;
  listener.root_port = dww_dart_main_port();
  listener.decide = decide;
  listener.merged = merged != 0;
  return listener.generation;
}

int32_t dww_navigation_complete(int64_t generation, int64_t request,
                                int32_t allow) {
  const auto pending = Take(generation, request);
  if (!pending) return 0;
  Finish(pending, allow != 0);
  return 1;
}

void dww_navigation_unregister(int64_t generation) { Reset(generation); }

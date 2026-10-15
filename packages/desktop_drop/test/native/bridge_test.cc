#include "desktop_drop_ffi.h"
#include "dart_api_dl.h"
#include "dart_version.h"
#include "internal/dart_api_dl_impl.h"

#include <cassert>
#include <chrono>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>

namespace {
std::mutex mutex;
std::condition_variable ready;
int64_t posted_request = 0;
int64_t posted_context = 0;
int64_t posted_generation = 0;
bool owns = true;
bool can_post = true;
int calls = 0;

bool Owns(Dart_Port port) { return owns && port == 42; }
Dart_Port MainPort() { return 42; }
bool Post(Dart_Port port, Dart_CObject* message) {
  assert(port == 99);
  assert(message->type == Dart_CObject_kArray);
  assert(message->value.as_array.length == 9);
  const auto values = message->value.as_array.values;
  assert(values[8]->type == Dart_CObject_kString);
  assert(std::string(values[8]->value.as_string) == "{\"types\":[\"text\"]}");
  {
    std::lock_guard<std::mutex> lock(mutex);
    posted_context = values[0]->value.as_int64;
    posted_generation = values[1]->value.as_int64;
    posted_request = values[2]->value.as_int64;
  }
  ready.notify_one();
  return can_post;
}
int64_t Decide(const DDRequest* request) {
  calls++;
  assert(request->view == 5 && request->session == 9);
  assert(request->x == 12 && request->y == 34);
  assert(request->length == 18);
  return 7;
}
const char* payload = "{\"types\":[\"text\"]}";
DDDecision Query(int64_t context) { return dd_bridge_decide(context, 9, 1, 12, 34, payload); }
void WaitForPost() {
  std::unique_lock<std::mutex> lock(mutex);
  assert(ready.wait_for(lock, std::chrono::seconds(2), [] { return posted_request != 0; }));
}
void ResetPost() { std::lock_guard<std::mutex> lock(mutex); posted_request = 0; }
}  // namespace

int main() {
  DartApiEntry entries[] = {
    {"Dart_GetCurrentThreadOwnsIsolate", reinterpret_cast<void (*)()>(Owns)},
    {"Dart_GetMainPortId", reinterpret_cast<void (*)()>(MainPort)},
    {"Dart_PostCObject", reinterpret_cast<void (*)()>(Post)}, {nullptr, nullptr},
  };
  DartApi api{DART_API_DL_MAJOR_VERSION, DART_API_DL_MINOR_VERSION, entries};
  const auto bridge = dd_bridge_create();
  assert(Query(bridge.context).target == 0);
  auto generation = dd_bridge_register(bridge.context, &api, 99, Decide, 1, 5);
  assert(generation > 0);
  assert(Query(bridge.context).target == 7 && calls == 1);
  owns = false;
  assert(Query(bridge.context).target == 0 && calls == 1);
  owns = true;

  generation = dd_bridge_register(bridge.context, &api, 99, Decide, 0, 5);
  DDDecision decision{};
  ResetPost();
  std::thread worker([&] { decision = Query(bridge.context); });
  WaitForPost();
  assert(!dd_bridge_complete(bridge.context, generation - 1, posted_request, 7));
  assert(dd_bridge_complete(bridge.context, generation, posted_request, 11));
  worker.join();
  assert(decision.target == 11);
  assert(!dd_bridge_complete(bridge.context, generation, posted_request, 12));

  ResetPost();
  const auto start = std::chrono::steady_clock::now();
  decision = Query(bridge.context);
  const auto elapsed = std::chrono::steady_clock::now() - start;
  assert(decision.target == 0);
  assert(elapsed >= std::chrono::milliseconds(90) && elapsed < std::chrono::seconds(2));
  assert(!dd_bridge_complete(bridge.context, generation, decision.request, 7));

  // A timed out request must not poison the next drag query.
  ResetPost();
  worker = std::thread([&] { decision = Query(bridge.context); });
  WaitForPost();
  dd_bridge_complete(bridge.context, generation, posted_request, 13);
  worker.join();
  assert(decision.target == 13);

  ResetPost();
  worker = std::thread([&] { decision = Query(bridge.context); });
  WaitForPost();
  dd_bridge_unregister(bridge.context, generation);
  worker.join();
  assert(decision.target == 0 && dd_bridge_generation(bridge.context) == 0);
  assert(!dd_bridge_complete(bridge.context, generation, posted_request, 7));

  auto next = dd_bridge_register(bridge.context, &api, 99, Decide, 0, 5);
  dd_bridge_unregister(bridge.context, generation);
  assert(dd_bridge_generation(bridge.context) == next);
  can_post = false;
  assert(Query(bridge.context).target == 0);
  can_post = true;
  ResetPost();
  worker = std::thread([&] { decision = Query(bridge.context); });
  WaitForPost();
  dd_bridge_destroy(bridge.context);
  worker.join();
  assert(decision.target == 0);
  assert(!dd_bridge_complete(bridge.context, next, posted_request, 7));
  assert(Query(bridge.context).target == 0);
  std::cout << "Bridge tests passed: direct, ownership, threaded completion, timeout, late reply, recovery, generations, disposal\n";
}

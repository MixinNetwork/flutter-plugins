// Portable ownership/protocol test. Real Flutter C++ wrapper and codec sources
// are used with a fake Win32/Flutter embedder, so this does not render a window.
#include "../flutter_view.h"

#include <flutter/method_result_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include "flutter/shell/platform/windows/flutter_windows_internal.h"

#include <cassert>
#include <cstring>
#include <iostream>
#include <set>
#include <utility>
#include <vector>

struct FlutterDesktopMessenger {
  std::map<std::string, std::pair<FlutterDesktopMessageCallback, void*>> handlers;
  std::vector<std::string> notifications;
};
struct FlutterDesktopPluginRegistrar {
  FlutterDesktopMessenger messenger;
  FlutterDesktopOnPluginRegistrarDestroyed on_destroy = nullptr;
};
struct FlutterDesktopEngine {
  FlutterDesktopPluginRegistrar registrar;
  std::set<int64_t> views;
  int64_t next_view_id = 0;
};
struct FlutterDesktopView {
  int64_t id;
};
struct FlutterDesktopViewController {
  FlutterDesktopEngineRef engine;
  FlutterDesktopView view;
};

namespace {
bool has_borrowed_api = true;
bool fail_next_view = false;
int engines_created = 0;
int engines_destroyed = 0;
int clients_registered = 0;
int controllers_destroyed = 0;
FlutterDesktopEngineRef last_engine = nullptr;
std::vector<uint8_t> last_reply;

flutter::EncodableList Snapshot() {
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  auto bytes = codec.EncodeMethodCall(flutter::MethodCall<flutter::EncodableValue>("getViews", nullptr));
  auto& messenger = last_engine->registrar.messenger;
  const auto handler = messenger.handlers.at("desktop_webview_window/titlebars");
  FlutterDesktopMessage message = {};
  message.struct_size = sizeof(message);
  message.channel = "desktop_webview_window/titlebars";
  message.message = bytes->data();
  message.message_size = bytes->size();
  message.response_handle = reinterpret_cast<FlutterDesktopMessageResponseHandle*>(1);
  last_reply.clear();
  handler.first(&messenger, &message, handler.second);
  flutter::EncodableList result;
  flutter::MethodResultFunctions<flutter::EncodableValue> response(
      [&result](const auto* value) { result = std::get<flutter::EncodableList>(*value); },
      [](const auto&, const auto&, const auto*) { assert(false); },
      [] { assert(false); });
  assert(codec.DecodeAndProcessResponseEnvelope(last_reply.data(), last_reply.size(), &response));
  return result;
}

int64_t Field(const flutter::EncodableValue& row, const char* name) {
  return std::get<flutter::EncodableMap>(row).at(flutter::EncodableValue(name)).LongValue();
}
}  // namespace

int ShowWindow(HWND, int command) { assert(command == SW_HIDE); return 0; }

HMODULE GetModuleHandleW(const wchar_t*) { return reinterpret_cast<HMODULE>(1); }
FARPROC GetProcAddress(HMODULE, const char* name) {
  if (!has_borrowed_api) return nullptr;
  FARPROC result = nullptr;
  if (std::strcmp(name, "FlutterDesktopEngineCreateViewController") == 0) {
    auto function = &FlutterDesktopEngineCreateViewController;
    std::memcpy(&result, &function, sizeof(result));
  } else {
    assert(std::strcmp(name, "FlutterDesktopEngineForId") == 0);
    auto function = &FlutterDesktopEngineForId;
    std::memcpy(&result, &function, sizeof(result));
  }
  return result;
}

extern "C" {
FlutterDesktopEngineRef FlutterDesktopEngineForId(int64_t id) {
  assert(id == 1234);
  return last_engine;
}
FlutterDesktopEngineRef FlutterDesktopEngineCreate(const FlutterDesktopEngineProperties* props) {
  ++engines_created;
  assert(false && "The plugin must not create an engine");
  return nullptr;
}
bool FlutterDesktopEngineDestroy(FlutterDesktopEngineRef engine) {
  assert(engine->views.empty());
  if (engine->registrar.on_destroy) engine->registrar.on_destroy(&engine->registrar);
  assert(engine->registrar.messenger.handlers.empty());
  ++engines_destroyed;
  delete engine;
  last_engine = nullptr;
  return true;
}
FlutterDesktopViewControllerRef FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine, const FlutterDesktopViewControllerProperties* props) {
  if (engine->next_view_id == 0) {
    assert(props->width == 0 && props->height == 0);
  } else {
    assert(props->width == 800 && props->height == 50);
  }
  assert(engine->registrar.messenger.handlers.count("desktop_webview_window/titlebars"));
  assert(!engine->registrar.messenger.handlers.count("webview_message/client_channel"));
  if (std::exchange(fail_next_view, false)) return nullptr;
  const auto id = engine->next_view_id++;
  engine->views.insert(id);
  return new FlutterDesktopViewController{engine, {id}};
}
void FlutterDesktopViewControllerDestroy(FlutterDesktopViewControllerRef controller) {
  if (controller->view.id != 0) {
    // Routing records must be withdrawn before native view-removal metrics.
    for (const auto& row : Snapshot()) {
      assert(Field(row, "viewId") != controller->view.id);
    }
  }
  controller->engine->views.erase(controller->view.id);
  ++controllers_destroyed;
  delete controller;
}
FlutterDesktopViewId FlutterDesktopViewControllerGetViewId(FlutterDesktopViewControllerRef controller) {
  return controller->view.id;
}
FlutterDesktopViewRef FlutterDesktopViewControllerGetView(FlutterDesktopViewControllerRef controller) {
  return &controller->view;
}
HWND FlutterDesktopViewGetHWND(FlutterDesktopViewRef view) { return view; }
void FlutterDesktopViewControllerForceRedraw(FlutterDesktopViewControllerRef) {}
bool FlutterDesktopViewControllerHandleTopLevelWindowProc(
    FlutterDesktopViewControllerRef, HWND, UINT, WPARAM, LPARAM, LRESULT*) { return false; }
void FlutterDesktopEngineReloadSystemFonts(FlutterDesktopEngineRef) {}
FlutterDesktopPluginRegistrarRef FlutterDesktopEngineGetPluginRegistrar(
    FlutterDesktopEngineRef engine, const char*) { return &engine->registrar; }
FlutterDesktopViewRef FlutterDesktopPluginRegistrarGetView(FlutterDesktopPluginRegistrarRef) {
  return nullptr;
}
FlutterDesktopMessengerRef FlutterDesktopPluginRegistrarGetMessenger(FlutterDesktopPluginRegistrarRef registrar) {
  return &registrar->messenger;
}
FlutterDesktopTextureRegistrarRef FlutterDesktopRegistrarGetTextureRegistrar(FlutterDesktopPluginRegistrarRef) {
  return nullptr;
}
void FlutterDesktopPluginRegistrarSetDestructionHandler(
    FlutterDesktopPluginRegistrarRef registrar, FlutterDesktopOnPluginRegistrarDestroyed callback) {
  registrar->on_destroy = callback;
}
void FlutterDesktopMessengerSetCallback(FlutterDesktopMessengerRef messenger, const char* channel,
                                       FlutterDesktopMessageCallback callback, void* data) {
  if (callback) {
    if (std::strcmp(channel, "webview_message/client_channel") == 0) ++clients_registered;
    messenger->handlers[channel] = {callback, data};
  } else {
    messenger->handlers.erase(channel);
  }
}
bool FlutterDesktopMessengerSend(FlutterDesktopMessengerRef messenger, const char* channel,
                                 const uint8_t* data, size_t length) {
  auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(data, length);
  messenger->notifications.push_back(call->method_name());
  return true;
}
bool FlutterDesktopMessengerSendWithReply(FlutterDesktopMessengerRef messenger, const char* channel,
    const uint8_t* data, size_t length, FlutterDesktopBinaryReply, void*) {
  return FlutterDesktopMessengerSend(messenger, channel, data, length);
}
void FlutterDesktopMessengerSendResponse(FlutterDesktopMessengerRef,
    const FlutterDesktopMessageResponseHandle*, const uint8_t* data, size_t length) {
  last_reply.assign(data, data + length);
}
FlutterDesktopMessengerRef FlutterDesktopMessengerAddRef(FlutterDesktopMessengerRef messenger) { return messenger; }
void FlutterDesktopMessengerRelease(FlutterDesktopMessengerRef) {}
bool FlutterDesktopMessengerIsAvailable(FlutterDesktopMessengerRef) { return true; }
FlutterDesktopMessengerRef FlutterDesktopMessengerLock(FlutterDesktopMessengerRef messenger) { return messenger; }
void FlutterDesktopMessengerUnlock(FlutterDesktopMessengerRef) {}
int64_t FlutterDesktopTextureRegistrarRegisterExternalTexture(FlutterDesktopTextureRegistrarRef,
                                                              const FlutterDesktopTextureInfo*) { return -1; }
bool FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(FlutterDesktopTextureRegistrarRef, int64_t) { return false; }
void FlutterDesktopTextureRegistrarUnregisterExternalTexture(FlutterDesktopTextureRegistrarRef, int64_t,
                                                              void (*callback)(void*), void* data) {
  if (callback) callback(data);
}
}  // extern "C"

int main() {
  // The runner has already created and started the application engine/view 0.
  FlutterDesktopEngine application_engine;
  application_engine.views.insert(0);
  application_engine.next_view_id = 1;
  last_engine = &application_engine;
  flutter::PluginRegistrarWindows registrar(&application_engine.registrar);
  std::string error;
  {
    webview_window::TitleBarViews owner(registrar.messenger());
    assert(!owner.CreateView(0, 0, 800, 50, &error));
    has_borrowed_api = false;
    assert(!owner.Initialize(1234, &error));
    has_borrowed_api = true;
    assert(owner.Initialize(1234, &error));
    auto first = owner.CreateView(7, 3, 800, 50, &error);
    auto second = owner.CreateView(42, 5, 800, 50, &error);
    assert(first && second);
    assert(engines_created == 0 && clients_registered == 0);
    assert(first->GetViewId() > 0 && second->GetViewId() > 0);
    assert(first->GetViewId() != second->GetViewId());
    auto views = Snapshot();
    assert(views.size() == 2);
    assert(Field(views[0], "viewId") == first->GetViewId());
    assert(Field(views[0], "webViewId") == 7 && Field(views[0], "titleBarTopPadding") == 3);
    first.reset();
    assert(engines_destroyed == 0 && Snapshot().size() == 1);
    assert(Field(Snapshot()[0], "webViewId") == 42);
    fail_next_view = true;
    assert(!owner.CreateView(50, 0, 800, 50, &error));
    assert(Snapshot().size() == 1 && engines_destroyed == 0);
    second.reset();
    assert(Snapshot().empty());
    assert(application_engine.views == std::set<int64_t>{0});
    auto reopened = owner.CreateView(99, 0, 800, 50, &error);
    assert(reopened && engines_created == 0);
    assert(Field(Snapshot()[0], "webViewId") == 99);
    reopened.reset();
  }
  assert(engines_created == 0 && engines_destroyed == 0);
  assert(controllers_destroyed == 3);
  assert(application_engine.views == std::set<int64_t>{0});
  assert(application_engine.registrar.messenger.handlers.empty());
  std::cout << "Application engine ownership and titlebar routing tests passed.\n";
}

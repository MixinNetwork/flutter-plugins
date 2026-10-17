#pragma once
#include "desktop_drop_ffi.h"
#include <flutter/encodable_value.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <functional>
#include <memory>
#include <vector>

// Platform tasks own copied buffers. No Dart-owned pointer reaches OLE.
class FfiTransport {
 public:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  using Handler = std::function<void(const flutter::MethodCall<Value>&, std::unique_ptr<Result>)>;
  explicit FfiTransport(FlutterDesktopMessengerRef messenger) : messenger_(messenger) {
    context_ = dd_rpc_create(0, [](void* user, int64_t context, int64_t epoch,
                                 int64_t request, const uint8_t* bytes, int32_t length) {
      auto* self = static_cast<FfiTransport*>(user);
      auto data = std::vector<uint8_t>(bytes, bytes + length);
      self->Dispatch([self, alive = self->alive_, context, epoch, request, data = std::move(data)] {
        if (!*alive) return;
        const auto& codec = flutter::StandardMethodCodec::GetInstance();
        auto call = codec.DecodeMethodCall(data.data(), data.size());
        const auto reply = [context, epoch, request](std::unique_ptr<std::vector<uint8_t>> bytes) {
          dd_rpc_reply(context, epoch, request, bytes ? bytes->data() : nullptr,
                       bytes ? static_cast<int32_t>(bytes->size()) : 0);
        };
        auto result = std::make_unique<flutter::MethodResultFunctions<Value>>(
          [reply](const Value* value) { reply(flutter::StandardMethodCodec::GetInstance().EncodeSuccessEnvelope(value)); },
          [reply](const std::string& code, const std::string& message, const Value* details) {
            reply(flutter::StandardMethodCodec::GetInstance().EncodeErrorEnvelope(code, message, details));
          }, [reply] { reply(nullptr); });
        if (call && self->handler_) self->handler_(*call, std::move(result));
        else result->NotImplemented();
      });
    }, this, [](void* user, int64_t engine) -> int32_t {
      auto* self = static_cast<FfiTransport*>(user);
      // PlatformDispatcher.engineId is the opaque Windows engine handle.
      const auto handle = reinterpret_cast<FlutterDesktopEngineRef>(engine);
      if (!handle || FlutterDesktopEngineGetMessenger(handle) != self->messenger_) return 0;
      self->engine_ = handle;
      return 1;
    });
  }
  ~FfiTransport() { *alive_ = false; dd_rpc_destroy(context_); }
  void SetHandler(Handler handler) { handler_ = std::move(handler); }
  void Invoke(const std::string& method, std::unique_ptr<Value> args,
              std::unique_ptr<Result> result = nullptr) {
    const auto bytes = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<Value>(method, std::move(args)));
    struct Pending {
      FlutterDesktopEngineRef engine;
      std::unique_ptr<Result> result;
    };
    auto* pending = result ? new Pending{engine_, std::move(result)} : nullptr;
    dd_rpc_send(context_, bytes->data(), static_cast<int32_t>(bytes->size()), pending ? +[](
        void* user, const uint8_t* bytes, int32_t length) {
      std::shared_ptr<Pending> pending(static_cast<Pending*>(user));
      const auto data = bytes ? std::vector<uint8_t>(bytes, bytes + length) : std::vector<uint8_t>();
      Post(pending->engine, [pending, data] {
        if (data.empty() || !flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(
            data.data(), data.size(), pending->result.get())) pending->result->NotImplemented();
      });
    } : nullptr, pending);
  }
 private:
  static void Post(FlutterDesktopEngineRef engine, std::function<void()> task) {
    auto* pending = new std::function<void()>(std::move(task));
    // No on_cancel: before flutter/flutter#193412 the engine builds its task
    // context from a temporary whose destructor runs on_cancel immediately,
    // freeing the task before it executes. A task discarded at engine
    // shutdown leaks.
    FlutterDesktopEnginePostPlatformThreadTask(engine, [](void* user) {
      std::unique_ptr<std::function<void()>> task(static_cast<std::function<void()>*>(user));
      (*task)();
    }, nullptr, pending);
  }
  void Dispatch(std::function<void()> task) { Post(engine_, std::move(task)); }
  FlutterDesktopMessengerRef messenger_;
  FlutterDesktopEngineRef engine_ = nullptr;
  int64_t context_ = 0;
  Handler handler_;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
};

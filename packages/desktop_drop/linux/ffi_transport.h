#pragma once
#include "desktop_drop_ffi.h"
#include <flutter_linux/flutter_linux.h>
#include <functional>
#include <memory>
#include <string>
#include <vector>

class FfiCall {
 public:
  FfiCall(int64_t context, int64_t epoch, int64_t request, std::string name, FlValue* args)
      : context_(context), epoch_(epoch), request_(request), name(std::move(name)), args(args) {}
  ~FfiCall() { if (args) fl_value_unref(args); }
  void Success(FlValue* value) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    Reply(FL_METHOD_CODEC_GET_CLASS(codec)->encode_success_envelope(FL_METHOD_CODEC(codec), value, nullptr));
  }
  void Error(const char* code, const char* message, FlValue* details = nullptr) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    Reply(FL_METHOD_CODEC_GET_CLASS(codec)->encode_error_envelope(FL_METHOD_CODEC(codec), code, message, details, nullptr));
  }
  void NotImplemented() { Reply(nullptr); }
 private:
  void Reply(GBytes* bytes) {
    if (replied_) { if (bytes) g_bytes_unref(bytes); return; }
    replied_ = true;
    gsize size = 0;
    const auto* data = bytes ? static_cast<const uint8_t*>(g_bytes_get_data(bytes, &size)) : nullptr;
    dd_rpc_reply(context_, epoch_, request_, data, static_cast<int32_t>(size));
    if (bytes) g_bytes_unref(bytes);
  }
  int64_t context_, epoch_, request_;
  bool replied_ = false;
 public:
  const std::string name;
  FlValue* const args;
};
using FfiCallRef = std::shared_ptr<FfiCall>;

class FfiTransport {
 public:
  using Handler = std::function<void(const FfiCallRef&)>;
  using Reply = std::function<void(FlValue*)>;
  FfiTransport(int64_t engine, Handler handler) : handler_(std::move(handler)) {
    context_ = dd_rpc_create(engine, [](void* user, int64_t context, int64_t epoch,
                                      int64_t request, const uint8_t* bytes, int32_t length) {
      auto* self = static_cast<FfiTransport*>(user);
      const auto data = std::vector<uint8_t>(bytes, bytes + length);
      Post([self, alive = self->alive_, context, epoch, request, data] {
        if (!*alive) return;
        g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
        g_autoptr(GBytes) bytes = g_bytes_new(data.data(), data.size());
        g_autofree gchar* name = nullptr;
        FlValue* args = nullptr;
        if (!FL_METHOD_CODEC_GET_CLASS(codec)->decode_method_call(FL_METHOD_CODEC(codec), bytes, &name, &args, nullptr)) {
          dd_rpc_reply(context, epoch, request, nullptr, 0); return;
        }
        self->handler_(std::make_shared<FfiCall>(context, epoch, request, name, args));
      });
    }, this, nullptr);
  }
  ~FfiTransport() { *alive_ = false; dd_rpc_destroy(context_); }
  int64_t Invoke(const char* method, FlValue* args, Reply reply = {}) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    g_autoptr(GBytes) bytes = FL_METHOD_CODEC_GET_CLASS(codec)->encode_method_call(FL_METHOD_CODEC(codec), method, args, nullptr);
    gsize size = 0;
    const auto* data = static_cast<const uint8_t*>(g_bytes_get_data(bytes, &size));
    auto* pending = reply ? new Reply(std::move(reply)) : nullptr;
    return dd_rpc_send(context_, data, static_cast<int32_t>(size), pending ? +[](
        void* user, const uint8_t* bytes, int32_t length) {
      std::shared_ptr<Reply> reply(static_cast<Reply*>(user));
      const auto data = bytes ? std::vector<uint8_t>(bytes, bytes + length) : std::vector<uint8_t>();
      Post([reply, data] {
        g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
        g_autoptr(GBytes) bytes = g_bytes_new(data.data(), data.size());
        g_autoptr(FlMethodResponse) response = FL_METHOD_CODEC_GET_CLASS(codec)->decode_response(FL_METHOD_CODEC(codec), bytes, nullptr);
        g_autoptr(GError) error = nullptr;
        (*reply)(response ? fl_method_response_get_result(response, &error) : nullptr);
      });
    } : nullptr, pending);
  }
  void Cancel(int64_t request) { dd_rpc_cancel(context_, request); }
 private:
  static void Post(std::function<void()> task) {
    g_idle_add_full(G_PRIORITY_DEFAULT, [](gpointer user) -> gboolean {
      (*static_cast<std::function<void()>*>(user))(); return G_SOURCE_REMOVE;
    }, new std::function<void()>(std::move(task)), [](gpointer user) { delete static_cast<std::function<void()>*>(user); });
  }
  int64_t context_;
  Handler handler_;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
};

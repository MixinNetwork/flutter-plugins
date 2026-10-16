#include <jni.h>
#include "desktop_drop_ffi.h"
#include <memory>
#include <unordered_map>
#include <vector>
#include <mutex>

namespace {
struct Owner { JavaVM* vm; jobject object; jmethodID dispatch; jmethodID complete; };
struct Pending { std::shared_ptr<Owner> owner; int64_t token; };
std::mutex owners_mutex;
std::unordered_map<int64_t, std::shared_ptr<Owner>> owners;
struct Environment {
  JavaVM* vm;
  JNIEnv* env = nullptr;
  bool attached;
  explicit Environment(JavaVM* vm) : vm(vm) {
    attached = vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_EDETACHED;
    if (attached) vm->AttachCurrentThread(&env, nullptr);
  }
  ~Environment() { if (attached) vm->DetachCurrentThread(); }
};
jbyteArray Bytes(JNIEnv* env, const uint8_t* bytes, int32_t length) {
  auto result = env->NewByteArray(length);
  if (length) env->SetByteArrayRegion(result, 0, length, reinterpret_cast<const jbyte*>(bytes));
  return result;
}
std::vector<uint8_t> Copy(JNIEnv* env, jbyteArray data) {
  std::vector<uint8_t> bytes(env->GetArrayLength(data));
  if (!bytes.empty()) env->GetByteArrayRegion(data, 0, bytes.size(), reinterpret_cast<jbyte*>(bytes.data()));
  return bytes;
}
}  // namespace
extern "C" JNIEXPORT jlong JNICALL
Java_one_mixin_desktop_drop_FfiTransport_nativeCreate(JNIEnv* env, jobject object, jlong engine) {
  JavaVM* vm;
  env->GetJavaVM(&vm);
  auto type = env->GetObjectClass(object);
  auto owner = std::shared_ptr<Owner>(new Owner{vm, env->NewGlobalRef(object),
    env->GetMethodID(type, "dispatch", "(JJJ[B)V"), env->GetMethodID(type, "complete", "(J[B)V")}, [](Owner* owner) {
      Environment current(owner->vm);
      current.env->DeleteGlobalRef(owner->object);
      delete owner;
    });
  env->DeleteLocalRef(type);
  const auto context = dd_rpc_create(engine, [](void* user, int64_t context, int64_t epoch,
                                               int64_t request, const uint8_t* bytes, int32_t length) {
    auto* owner = static_cast<Owner*>(user);
    Environment current(owner->vm);
    auto data = Bytes(current.env, bytes, length);
    current.env->CallVoidMethod(owner->object, owner->dispatch, context, epoch, request, data);
    current.env->DeleteLocalRef(data);
  }, owner.get(), nullptr);
  std::lock_guard<std::mutex> lock(owners_mutex);
  owners.emplace(context, std::move(owner));
  return context;
}
extern "C" JNIEXPORT void JNICALL
Java_one_mixin_desktop_drop_FfiTransport_nativeDestroy(JNIEnv*, jobject, jlong context) {
  dd_rpc_destroy(context);
  std::lock_guard<std::mutex> lock(owners_mutex);
  owners.erase(context);
}
extern "C" JNIEXPORT jlong JNICALL
Java_one_mixin_desktop_drop_FfiTransport_nativeSend(JNIEnv* env, jobject, jlong context, jbyteArray data, jlong token) {
  const auto bytes = Copy(env, data);
  std::shared_ptr<Owner> owner;
  { std::lock_guard<std::mutex> lock(owners_mutex);
    const auto found = owners.find(context);
    if (found != owners.end()) owner = found->second;
  }
  if (!owner) return 0;
  auto* pending = token ? new Pending{owner, token} : nullptr;
  return dd_rpc_send(context, bytes.data(), bytes.size(), pending ? +[](void* user, const uint8_t* bytes, int32_t length) {
    std::unique_ptr<Pending> pending(static_cast<Pending*>(user));
    Environment current(pending->owner->vm);
    auto data = Bytes(current.env, bytes, length);
    current.env->CallVoidMethod(pending->owner->object, pending->owner->complete, pending->token, data);
    current.env->DeleteLocalRef(data);
  } : nullptr, pending);
}
extern "C" JNIEXPORT void JNICALL
Java_one_mixin_desktop_drop_FfiTransport_nativeCancel(JNIEnv*, jobject, jlong context, jlong request) {
  dd_rpc_cancel(context, request);
}
extern "C" JNIEXPORT void JNICALL
Java_one_mixin_desktop_drop_FfiTransport_nativeReply(JNIEnv* env, jobject, jlong context, jlong epoch, jlong request, jbyteArray data) {
  const auto bytes = Copy(env, data);
  dd_rpc_reply(context, epoch, request, bytes.data(), bytes.size());
}

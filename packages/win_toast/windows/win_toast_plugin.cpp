#include "include/win_toast/win_toast_plugin.h"

// This must be included before many other Windows headers.
#include <Windows.h>
#include <VersionHelpers.h>

#include "strconv.h"
#include "notification_manager.h"
#include "notification_manager_win_rt.h"
#include "notification_manager_wrl.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>

#ifdef WIN_TOAST_ENABLE_WRL
#include "wrl_compat.h"
#include "NotificationActivationCallback.h"
#endif // WIN_TOAST_ENABLE_WRL

namespace {

#ifdef WIN_TOAST_ENABLE_WRL

using namespace ABI::Windows::Foundation;
using namespace Microsoft::WRL;

class DECLSPEC_UUID(WIN_TOAST_WRL_ACTIVATOR_CLSID) NotificationActivator : public RuntimeClass<
    RuntimeClassFlags<ClassicCom>,
    INotificationActivationCallback> {
 public:
  virtual HRESULT STDMETHODCALLTYPE Activate(
      _In_ LPCWSTR appUserModelId,
      _In_ LPCWSTR invokedArgs,
      _In_reads_(dataCount) const NOTIFICATION_USER_INPUT_DATA *data,
      ULONG dataCount
  ) override {
    std::wstring arguments(invokedArgs);

    std::map<std::wstring, std::wstring> inputs;
    for (unsigned int i = 0; i < dataCount; i++) {
      inputs[data[i].Key] = data[i].Value;
    }

    auto *instance = NotificationManagerWrl::GetInstance();
    instance->DispatchActivatedEvent(arguments, inputs);

    return S_OK;
  }

  ~NotificationActivator() {
  }
};

// Flag class as COM creatable
CoCreatableClass(NotificationActivator)

#endif // WIN_TOAST_ENABLE_WRL

class WinToastPlugin : public flutter::Plugin {
 public:
  using FlutterMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel);

  ~WinToastPlugin() override;

 private:
  std::shared_ptr<FlutterMethodChannel> channel_;
  NotificationManager *manager_;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnNotificationActivated(const std::wstring &argument, const std::map<std::wstring, std::wstring> &user_input);

  void OnNotificationDismissed(const std::wstring &tag, const std::wstring &group, int reason);
};

// static
void WinToastPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_shared<FlutterMethodChannel>(
      registrar->messenger(), "win_toast",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WinToastPlugin>(channel);
  channel->SetMethodCallHandler(
      [pluginref = plugin.get()](const auto &call, auto result) {
        pluginref->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WinToastPlugin::WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel)
    : channel_(std::move(channel)), manager_(nullptr) {

  if (IsWindows10OrGreater()) {
    std::cout << "NotificationManagerWin" << std::endl;

#ifdef WIN_TOAST_ENABLE_WRL
    std::cout << "WIN_TOAST_ENABLE_WRL" << std::endl;
    if (NotificationManager::HasIdentity()) {
      manager_ = NotificationManagerWrl::GetInstance();
    }
#endif
#ifdef WIN_TOAST_ENABLE_WIN_RT
    std::cout << "WIN_TOAST_ENABLE_WINRT" << std::endl;
    if (!NotificationManager::HasIdentity()) {
      manager_ = NotificationManagerWinRT::GetInstance();
    }
#endif
  }
}

WinToastPlugin::~WinToastPlugin() = default;

void WinToastPlugin::OnNotificationActivated(
    const std::wstring &argument,
    const std::map<std::wstring, std::wstring> &user_input
) {
  std::map<flutter::EncodableValue, flutter::EncodableValue> user_input_value;
  for (auto &&item : user_input) {
    user_input_value.insert(std::make_pair(
        flutter::EncodableValue(wide_to_utf8(item.first)),
        flutter::EncodableValue(wide_to_utf8(item.second))
    ));
  }
  flutter::EncodableMap map = {
      {flutter::EncodableValue("argument"), flutter::EncodableValue(wide_to_utf8(argument))},
      {flutter::EncodableValue("user_input"), flutter::EncodableValue(user_input_value)},
  };
  channel_->InvokeMethod("OnNotificationActivated", std::make_unique<flutter::EncodableValue>(map));
}

void WinToastPlugin::OnNotificationDismissed(const std::wstring &tag, const std::wstring &group, int reason) {
  flutter::EncodableMap map = {
      {flutter::EncodableValue("tag"), flutter::EncodableValue(wide_to_utf8(tag))},
      {flutter::EncodableValue("group"), flutter::EncodableValue(wide_to_utf8(group))},
      {flutter::EncodableValue("reason"), flutter::EncodableValue(reason)},
  };
  channel_->InvokeMethod(
      "OnNotificationDismissed",
      std::make_unique<flutter::EncodableValue>(map)
  );
}

void WinToastPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!manager_) {
    result->Error("1", "Error, your system in not supported!");
    return;
  }

  if (method_call.method_name() == "initialize") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto aumid = std::get<std::string>(arguments->at(flutter::EncodableValue("aumid")));
    auto display_name = std::get<std::string>(arguments->at(flutter::EncodableValue("display_name")));
    auto icon_path = std::get<std::string>(arguments->at(flutter::EncodableValue("icon_path")));
    manager_->Register(utf8_to_wide(aumid), utf8_to_wide(display_name), utf8_to_wide(icon_path));
    manager_->OnActivated([this](const std::wstring &argument, const std::map<std::wstring, std::wstring> &user_input) {
      OnNotificationActivated(argument, user_input);
    });
    manager_->OnDismissed([this](const auto &tag, const auto &group, const auto &reason) {
      OnNotificationDismissed(tag, group, reason);
    });
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "showCustomToast") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto xml = std::get<std::string>(arguments->at(flutter::EncodableValue("xml")));
    auto tag = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
    auto group = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));
    auto expiration = std::get<int>(arguments->at(flutter::EncodableValue("expiration")));

    auto hr = manager_->ShowToast(utf8_to_wide(xml), utf8_to_wide(tag),
                                  utf8_to_wide(group), expiration);
    result->Success(flutter::EncodableValue(int64_t(hr)));
  } else if (method_call.method_name() == "dismiss") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto tag = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
    auto group = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));
    manager_->Remove(utf8_to_wide(tag), utf8_to_wide(group));
    result->Success();
  } else if (method_call.method_name() == "clear") {
    manager_->Clear();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

} // namespace

void WinToastPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WinToastPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

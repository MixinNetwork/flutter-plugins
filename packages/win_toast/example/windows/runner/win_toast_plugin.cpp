#include "include/win_toast/win_toast_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <VersionHelpers.h>

#include "strconv.h"
#include "DesktopNotificationManagerCompat.h"
#include <winrt/Windows.Data.Xml.Dom.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>

namespace {

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;

class WinToastPlugin : public flutter::Plugin {
 public:
  using FlutterMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel);

  ~WinToastPlugin() override;

 private:
  std::shared_ptr<FlutterMethodChannel> channel_;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnNotificationStatusChanged(flutter::EncodableMap map);

  void OnNotificationActivated(DesktopNotificationActivatedEventArgsCompat data);

  void OnNotificationDismissed(const ToastNotification &sender, const ToastDismissedEventArgs &args);
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
    : channel_(std::move(channel)) {
}

WinToastPlugin::~WinToastPlugin() = default;

void WinToastPlugin::OnNotificationStatusChanged(flutter::EncodableMap map) {
  channel_->InvokeMethod("OnNotificationStatusChanged", std::make_unique<flutter::EncodableValue>(map));
}

void WinToastPlugin::OnNotificationActivated(DesktopNotificationActivatedEventArgsCompat data) {
  std::map<flutter::EncodableValue, flutter::EncodableValue> user_input;
  for (auto item : data.UserInput()) {
    user_input.insert(std::make_pair(
        flutter::EncodableValue(wide_to_utf8(item.Key().c_str())),
        flutter::EncodableValue(wide_to_utf8(item.Value().c_str()))
    ));
  }
  flutter::EncodableMap map = {
      {flutter::EncodableValue("argument"), flutter::EncodableValue(wide_to_utf8(data.Argument()))},
      {flutter::EncodableValue("user_input"), flutter::EncodableValue(user_input)},
  };
  channel_->InvokeMethod("OnNotificationActivated", std::make_unique<flutter::EncodableValue>(map));
}

void WinToastPlugin::OnNotificationDismissed(const ToastNotification &sender, const ToastDismissedEventArgs &args) {
  auto reason = args.Reason();
  if (reason == ToastDismissalReason::UserCanceled) {
    std::wcout << L"The user dismissed this toast." << sender.Tag().c_str() << std::endl;
  } else if (reason == ToastDismissalReason::ApplicationHidden) {
    std::wcout << L"The application hid the toast using ToastNotifier.hide()" << std::endl;
  } else if (reason == ToastDismissalReason::TimedOut) {
    std::wcout << L"The toast has timed out." << std::endl;
  }
  flutter::EncodableMap map = {
      {flutter::EncodableValue("tag"), flutter::EncodableValue(wide_to_utf8(sender.Tag().c_str()))},
      {flutter::EncodableValue("group"), flutter::EncodableValue(wide_to_utf8(sender.Group().c_str()))},
      {flutter::EncodableValue("reason"), flutter::EncodableValue(static_cast<int>(reason))},
  };
  channel_->InvokeMethod(
      "OnNotificationDismissed",
      std::make_unique<flutter::EncodableValue>(map)
  );
}

void WinToastPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!IsWindows10OrGreater()) {
    result->Error("1", "Error, your system in not supported!");
    return;
  }

  if (method_call.method_name() == "initialize") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto aumid = std::get<std::string>(arguments->at(flutter::EncodableValue("aumid")));
    auto display_name = std::get<std::string>(arguments->at(flutter::EncodableValue("display_name")));
    auto icon_path = std::get<std::string>(arguments->at(flutter::EncodableValue("icon_path")));
    DesktopNotificationManagerCompat::Register(utf8_to_wide(aumid), utf8_to_wide(display_name),
                                               utf8_to_wide(icon_path));
    DesktopNotificationManagerCompat::OnActivated([this](DesktopNotificationActivatedEventArgsCompat data) {
      this->OnNotificationActivated(std::move(data));
    });
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "showCustomToast") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto xml = std::get<std::string>(arguments->at(flutter::EncodableValue("xml")));
    auto tag = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
    auto group = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));
    auto expiration = std::get<int>(arguments->at(flutter::EncodableValue("expiration")));
    auto expiration_on_reboot = std::get<bool>(arguments->at(flutter::EncodableValue("expiration_on_reboot")));

    // Construct the toast template
    XmlDocument doc;
    doc.LoadXml(utf8_to_wide(xml));

    // Construct the notification
    ToastNotification notification{doc};

    if (!tag.empty()) {
      notification.Tag(utf8_to_wide(tag));
    }
    if (!group.empty()) {
      notification.Group(utf8_to_wide(group));
    }

    if (expiration != 0) {
      Windows::Foundation::DateTime
          expiration_time = Windows::Foundation::DateTime() + Windows::Foundation::TimeSpan(expiration);
      std::cout << "expiration_time: "
                << std::chrono::duration_cast<std::chrono::milliseconds>(expiration_time.time_since_epoch()).count()
                << std::endl;
      notification.ExpirationTime(expiration_time);
    }

    notification.ExpiresOnReboot(expiration_on_reboot);

    notification.Dismissed([this](const ToastNotification &sender, const ToastDismissedEventArgs &args) {
      this->OnNotificationDismissed(sender, args);
    });

    // And send it!
    DesktopNotificationManagerCompat::CreateToastNotifier().Show(notification);
    result->Success(flutter::EncodableValue(1));
  } else if (method_call.method_name() == "dismiss") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto tag = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
    auto group = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));
    DesktopNotificationManagerCompat::History().Remove(utf8_to_wide(tag), utf8_to_wide(group));
    result->Success();
  } else if (method_call.method_name() == "clear") {
    DesktopNotificationManagerCompat::History().Clear();
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

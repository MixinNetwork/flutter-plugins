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

inline std::wstring string2wString(const std::string &s) {
  return utf8_to_wide(s);
}

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

  void OnNotificationActivated(DesktopNotificationActivatedEventArgsCompat args);
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

void WinToastPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!IsWindows10OrGreater()) {
    result->Error("1", "Error, your system in not supported!");
    return;
  }

  using namespace winrt;
  using namespace Windows::Data::Xml::Dom;
  using namespace Windows::UI::Notifications;

  if (method_call.method_name() == "initialize") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto aumid = std::get<std::string>(arguments->at(flutter::EncodableValue("aumid")));
    auto display_name = std::get<std::string>(arguments->at(flutter::EncodableValue("display_name")));
    auto icon_path = std::get<std::string>(arguments->at(flutter::EncodableValue("icon_path")));
    DesktopNotificationManagerCompat::Register(string2wString(aumid), string2wString(display_name),
                                               string2wString(icon_path));
    DesktopNotificationManagerCompat::OnActivated([this](DesktopNotificationActivatedEventArgsCompat data) {
      this->OnNotificationActivated(std::move(data));
    });
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "showCustomToast") {
    // Construct the toast template
    XmlDocument doc;
    doc.LoadXml(L"<toast>\
    <visual>\
        <binding template=\"ToastGeneric\">\
            <text></text>\
            <text></text>\
            <image placement=\"appLogoOverride\" hint-crop=\"circle\"/>\
            <image/>\
        </binding>\
    </visual>\
    <actions>\
        <input\
            id=\"tbReply\"\
            type=\"text\"\
            placeHolderContent=\"Type a reply\"/>\
        <action\
            content=\"Reply\"\
            activationType=\"background\"/>\
        <action\
            content=\"Like\"\
            activationType=\"background\"/>\
        <action\
            content=\"View\"\
            activationType=\"background\"/>\
    </actions>\
</toast>");

    // Populate with text and values
    doc.DocumentElement().SetAttribute(L"launch", L"action=viewConversation&conversationId=9813");
    doc.SelectSingleNode(L"//text[1]").InnerText(L"Andrew sent you a picture");
    doc.SelectSingleNode(L"//text[2]").InnerText(L"Check this out, Happy Canyon in Utah!");
    doc.SelectSingleNode(L"//image[1]").as<XmlElement>().SetAttribute(L"src", L"https://unsplash.it/64?image=1005");
    doc.SelectSingleNode(L"//image[2]").as<XmlElement>().SetAttribute(L"src",
                                                                      L"https://picsum.photos/364/202?image=883");
    doc.SelectSingleNode(L"//action[1]").as<XmlElement>().SetAttribute(L"arguments",
                                                                       L"action=reply&conversationId=9813");
    doc.SelectSingleNode(L"//action[2]").as<XmlElement>().SetAttribute(L"arguments",
                                                                       L"action=like&conversationId=9813");
    doc.SelectSingleNode(L"//action[3]").as<XmlElement>().SetAttribute(L"arguments",
                                                                       L"action=viewImage&imageUrl=https://picsum.photos/364/202?image=883");
    // Construct the notification
    ToastNotification notif{doc};
    notif.Dismissed([](ToastNotification const &sender, ToastDismissedEventArgs const &args) {
      auto reason = args.Reason();
      if (reason == ToastDismissalReason::UserCanceled) {
        std::wcout << L"The user dismissed this toast." << sender.Tag().c_str() << std::endl;
      } else if (reason == ToastDismissalReason::ApplicationHidden) {
        std::wcout << L"The application hid the toast using ToastNotifier.hide()" << std::endl;
      } else if (reason == ToastDismissalReason::TimedOut) {
        std::wcout << L"The toast has timed out." << std::endl;
      }
    });

    // And send it!
    DesktopNotificationManagerCompat::CreateToastNotifier().Show(notif);
    result->Success(flutter::EncodableValue(1));
  } else if (method_call.method_name() == "remove") {
    auto id = std::get_if<int64_t>(method_call.arguments());
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

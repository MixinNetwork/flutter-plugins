#include "include/win_toast/win_toast_plugin.h"

// This must be included before many other Windows headers.
#include <Windows.h>
#include <VersionHelpers.h>

#include "strconv.h"
#include "dll_importer.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "DesktopNotificationManagerCompat.h"
#include <winrt/Windows.Data.Xml.Dom.h>
#include <iostream>
#include <utility>

#include <map>
#include <memory>
#include <inspectable.h>

namespace {

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;
using namespace notification_rt;

class WinToastPlugin : public flutter::Plugin {
 public:
  using FlutterMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel);

  ~WinToastPlugin() override;

 private:
  std::shared_ptr<FlutterMethodChannel> channel_;

  bool is_supported_;

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
    : channel_(std::move(channel)), is_supported_(false) {

  if (IsWindows10OrGreater()) {
    HRESULT hr = DllImporter::Initialize();
    if (FAILED(hr)) {
      std::wcout << L"Failed to initialize DllImporter." << std::endl;
      return;
    }
    is_supported_ = true;
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

#define WIN_TOAST_RESULT_START try {
#define WIN_TOAST_RESULT_END \
  } catch (hresult_error const &e) { \
    result->Error(std::to_string(e.code()), wide_to_utf8(e.message().c_str())); \
  } catch (...) { \
    result->Error("error", "Unknown error"); \
  }

void WinToastPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!is_supported_) {
    result->Error("1", "Error, your system in not supported!");
    return;
  }

  if (method_call.method_name() == "initialize") {
    WIN_TOAST_RESULT_START
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto aumid = std::get<std::string>(arguments->at(flutter::EncodableValue("aumid")));
      auto display_name = std::get<std::string>(arguments->at(flutter::EncodableValue("display_name")));
      auto icon_path = std::get<std::string>(arguments->at(flutter::EncodableValue("icon_path")));
      auto clsid = std::get<std::string>(arguments->at(flutter::EncodableValue("clsid")));

      DesktopNotificationManagerCompat::Register(utf8_to_wide(aumid), utf8_to_wide(display_name),
                                                 utf8_to_wide(icon_path), utf8_to_wide(clsid));
      DesktopNotificationManagerCompat::OnActivated([this](DesktopNotificationActivatedEventArgsCompat data) {
        std::wstring tag = data.Argument();
        std::map<std::wstring, std::wstring> user_inputs;
        for (auto &&input : data.UserInput()) {
          user_inputs[input.Key().c_str()] = input.Value().c_str();
        }
        OnNotificationActivated(tag, user_inputs);
      });
      result->Success();
    WIN_TOAST_RESULT_END
  } else if (method_call.method_name() == "showCustomToast") {
    WIN_TOAST_RESULT_START
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto xml = std::get<std::string>(arguments->at(flutter::EncodableValue("xml")));
      auto tag = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
      auto group = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));

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

      notification.Dismissed([this](const ToastNotification &sender, const ToastDismissedEventArgs &args) {
        OnNotificationDismissed(
            sender.Tag().c_str(),
            sender.Group().c_str(),
            static_cast<int>(args.Reason())
        );
      });

      notification.Activated([this](const ToastNotification &sender, Windows::Foundation::IInspectable args) {

      });

      DesktopNotificationManagerCompat::CreateToastNotifier().Show(notification);
      result->Success();
    WIN_TOAST_RESULT_END
  } else if (method_call.method_name() == "dismiss") {
    WIN_TOAST_RESULT_START
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto tagString = std::get<std::string>(arguments->at(flutter::EncodableValue("tag")));
      auto groupString = std::get<std::string>(arguments->at(flutter::EncodableValue("group")));
      auto tag = utf8_to_wide(tagString);
      auto group = utf8_to_wide(groupString);
      if (!tag.empty() && !group.empty()) {
        DesktopNotificationManagerCompat::History().Remove(tag, group);
      } else if (!group.empty()) {
        DesktopNotificationManagerCompat::History().RemoveGroup(group);
      } else if (!tag.empty()) {
        DesktopNotificationManagerCompat::History().Remove(tag);
      }
      result->Success();
    WIN_TOAST_RESULT_END
  } else if (method_call.method_name() == "clear") {
    WIN_TOAST_RESULT_START
      DesktopNotificationManagerCompat::History().Clear();
      result->Success();
    WIN_TOAST_RESULT_END
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

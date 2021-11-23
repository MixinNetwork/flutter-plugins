#include "include/win_toast/win_toast_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include "wintoastlib.h"
#include "strconv.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

namespace {

inline std::wstring string2wString(const std::string &s) {
  return utf8_to_wide(s);
}

using namespace WinToastLib;

class ToastServiceHandler;

class Toast {

 public:
  Toast(
      int type, std::string title,
      std::string subtitle,
      std::string image,
      std::vector<std::string> actions) : toastTemplate_(WinToastTemplate::WinToastTemplateType(type)) {
    toastTemplate_.setFirstLine(string2wString(title));
    if (subtitle.size() != 0) {
      toastTemplate_.setSecondLine(string2wString(subtitle));
    }
    if (image.size() != 0) {
      toastTemplate_.setImagePath(string2wString(image));
    }
    for (auto action: actions) {
      toastTemplate_.addAction(string2wString(action));
    }
  }

  int64_t show(std::unique_ptr<ToastServiceHandler> handler);

  int64_t id() { return id_; }

 private:
  WinToastTemplate toastTemplate_;
  int64_t id_ = -1;
};

class ToastServiceHandler : public IWinToastHandler {
 public:
  ToastServiceHandler(std::shared_ptr<Toast> toast,
                      std::function<void(flutter::EncodableMap)> handle_callback)
      : toast_(std::move(toast)),
        handle_callback_(std::move(handle_callback)) {}

  void toastActivated() const override {
    handle_callback_(flutter::EncodableMap{
        {flutter::EncodableValue("action"), flutter::EncodableValue("activated")},
        {flutter::EncodableValue("id"), flutter::EncodableValue(toast_->id())},
    });
  }

  void toastActivated(int index) const override {
    handle_callback_(flutter::EncodableMap{
        {flutter::EncodableValue("action"), flutter::EncodableValue("activated")},
        {flutter::EncodableValue("id"), flutter::EncodableValue(toast_->id())},
        {flutter::EncodableValue("actionIndex"), flutter::EncodableValue(index)},
    });
  }

  void toastDismissed(WinToastDismissalReason state) const override {
    handle_callback_(flutter::EncodableMap{
        {flutter::EncodableValue("action"), flutter::EncodableValue("dismissed")},
        {flutter::EncodableValue("id"), flutter::EncodableValue(toast_->id())},
        {flutter::EncodableValue("reason"), flutter::EncodableValue(state)},
    });
  }

  void toastFailed() const override {
    handle_callback_(flutter::EncodableMap{
        {flutter::EncodableValue("action"), flutter::EncodableValue("failed")},
        {flutter::EncodableValue("id"), flutter::EncodableValue(toast_->id())},
    });
  }

  ~ToastServiceHandler() {
    std::cout << "~ToastServiceHandler()" << std::endl;
    handle_callback_(
        flutter::EncodableMap{
            {flutter::EncodableValue("action"), flutter::EncodableValue("end")},
            {flutter::EncodableValue("id"), flutter::EncodableValue(toast_->id())},
        });
  }

 private:
  std::function<void(flutter::EncodableMap)> handle_callback_;

  std::shared_ptr<Toast> toast_;
};

int64_t Toast::show(std::unique_ptr<ToastServiceHandler> handler) {
  id_ = WinToast::instance()->showToast(toastTemplate_, std::move(handler));
  return id_;
}

class WinToastPlugin : public flutter::Plugin {
 public:
  using FlutterMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel, HWND hwnd);

  ~WinToastPlugin() override;

 private:
  std::shared_ptr<FlutterMethodChannel> channel_;
  HWND window_handle_;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnNotificationStatusChanged(flutter::EncodableMap map);
};

// static
void WinToastPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_shared<FlutterMethodChannel>(
      registrar->messenger(), "win_toast",
      &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd;
  if (registrar->GetView()) {
    hwnd = registrar->GetView()->GetNativeWindow();
  }

  auto plugin = std::make_unique<WinToastPlugin>(channel, registrar->GetView()->GetNativeWindow());
  channel->SetMethodCallHandler(
      [pluginref = plugin.get()](const auto &call, auto result) {
        pluginref->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WinToastPlugin::WinToastPlugin(std::shared_ptr<FlutterMethodChannel> channel, HWND hwnd)
    : channel_(std::move(channel)), window_handle_(hwnd) {
}

WinToastPlugin::~WinToastPlugin() {
  WinToast::instance()->clear();
}

void WinToastPlugin::OnNotificationStatusChanged(flutter::EncodableMap map) {
  channel_->InvokeMethod("OnNotificationStatusChanged", std::make_unique<flutter::EncodableValue>(map));
}

void WinToastPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!WinToast::isCompatible()) {
    result->Error("1", "Error, your system in not supported!");
    return;
  }
  if (method_call.method_name().compare("initialize") == 0) {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto app_name = std::get<std::string>(arguments->at(flutter::EncodableValue("app_name")));
    auto company_name = std::get<std::string>(arguments->at(flutter::EncodableValue("company_name")));
    auto product_name = std::get<std::string>(arguments->at(flutter::EncodableValue("product_name")));
    WinToast::instance()->setAppName(string2wString(app_name));
    auto aumi = WinToast::configureAUMI(string2wString(company_name), string2wString(product_name));
    WinToast::instance()->setAppUserModelId(aumi);
    bool ret = WinToast::instance()->initialize();
    result->Success(flutter::EncodableValue(ret));
  } else if (method_call.method_name().compare("showToast") == 0) {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto title = std::get<std::string>(arguments->at(flutter::EncodableValue("title")));
    auto subtitle = std::get<std::string>(arguments->at(flutter::EncodableValue("subtitle")));
    auto imagePath = std::get<std::string>(arguments->at(flutter::EncodableValue("imagePath")));
    auto type = std::get<int>(arguments->at(flutter::EncodableValue("type")));
    auto actions = std::get<flutter::EncodableList>(arguments->at(flutter::EncodableValue("actions")));
    std::vector<std::string> action_strs;
    for (auto const &action: actions) {
      action_strs.push_back(std::get<std::string>(action));
    }
    auto toast = std::make_shared<Toast>(type, title, subtitle, imagePath, std::move(action_strs));

    auto handler = std::make_unique<ToastServiceHandler>(
        toast,
        std::bind(&WinToastPlugin::OnNotificationStatusChanged, this, std::placeholders::_1));
    auto id = toast->show(std::move(handler));
    result->Success(flutter::EncodableValue(id));
  } else if (method_call.method_name().compare("dismiss") == 0) {
    auto id = std::get_if<int64_t>(method_call.arguments());
    WinToast::instance()->hideToast(*id);
    result->Success();
  } else if (method_call.method_name().compare("clear") == 0) {
    WinToast::instance()->clear();
    result->Success();
  } else if (method_call.method_name().compare("bringWindowToFront") == 0) {
    if (window_handle_) {
      SetForegroundWindow(window_handle_);
    }
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

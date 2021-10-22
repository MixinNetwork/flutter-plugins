#include "include/desktop_webview_window/desktop_webview_window_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "strconv.h"
#include "webview_window.h"

#include <map>
#include <memory>

#include "wrl.h"
#include "wil/wrl.h"
#include "WebView2.h"

namespace {

int64_t next_window_id_ = 0;

class WebviewWindowPlugin : public flutter::Plugin {
 public:

  using MethodChannelPtr = std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit WebviewWindowPlugin(MethodChannelPtr method_channel);

  ~WebviewWindowPlugin() override;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  MethodChannelPtr method_channel_;

  std::map<int64_t, std::unique_ptr<WebviewWindow>> windows_;

};

// static
void WebviewWindowPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "webview_window",
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<WebviewWindowPlugin>(channel);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WebviewWindowPlugin::WebviewWindowPlugin(MethodChannelPtr method_channel)
    : method_channel_(std::move(method_channel)),
      windows_() {}

WebviewWindowPlugin::~WebviewWindowPlugin() = default;

void WebviewWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "create") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto width = arguments->at(flutter::EncodableValue("windowWidth")).LongValue();
    auto height = arguments->at(flutter::EncodableValue("windowHeight")).LongValue();
    auto title = std::get<std::string>(arguments->at(flutter::EncodableValue("title")));

    auto window_id = next_window_id_;
    auto window = std::make_unique<WebviewWindow>(method_channel_, window_id, [this, window_id]() {
      windows_.erase(window_id);
    });
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result2(std::move(result));
    window->CreateAndShow(
        utf8_to_wide(title), int(height), int(width),
        [this, window_id, result(result2)](bool succeed) mutable {
          if (!succeed) {
            windows_.erase(window_id);
            result->Error("0", "failed to show window");
            return;
          }
          result->Success(flutter::EncodableValue(window_id));
        });
    next_window_id_++;
    windows_[window_id] = std::move(window);
  } else if (method_call.method_name() == "launch") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());

    auto window_id = arguments->at(flutter::EncodableValue("viewId")).LongValue();
    auto url = std::get<std::string>(arguments->at(flutter::EncodableValue("url")));

    if (!windows_.count(window_id)) {
      result->Error("0", "can not find webview window for id");
      return;
    }
    windows_[window_id]->Navigate(utf8_to_wide(url));
    result->Success();
  } else if (method_call.method_name() == "addScriptToExecuteOnDocumentCreated") {
    auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());

    auto window_id = arguments->at(flutter::EncodableValue("viewId")).LongValue();
    auto javaScript = std::get<std::string>(arguments->at(flutter::EncodableValue("javaScript")));

    if (!windows_.count(window_id)) {
      result->Error("0", "can not find webview window for id");
      return;
    }
    windows_[window_id]->AddScriptToExecuteOnDocumentCreated(utf8_to_wide(javaScript));
    result->Success();
  } else if (method_call.method_name() == "clearAll") {
    std::map<int64_t, std::unique_ptr<WebviewWindow>> local;
    std::swap(local, windows_);
    std::cout << "windows_ : " << windows_.size() << std::endl;
    for (auto const &entry: local) {
      if (entry.second) {
        entry.second->Close();
      }
    }
    local.clear();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void DesktopWebviewWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WebviewWindowPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

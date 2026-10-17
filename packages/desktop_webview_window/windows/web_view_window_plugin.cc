//
// Created by yangbin on 2021/11/15.
//
#include "web_view_window_plugin.h"

#include <windows.h>

#include <map>
#include <vector>

#include "navigation_decider.h"

namespace {

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

bool IsWebViewRuntimeAvailable() {
  wil::unique_cotaskmem_string version_info;
  const HRESULT hr =
      GetAvailableCoreWebView2BrowserVersionString(nullptr, &version_info);
  return SUCCEEDED(hr) && version_info != nullptr;
}

const Value* Find(const Map& map, const char* key) {
  const auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}

bool Bool(const Map& map, const char* key, bool fallback) {
  const auto* value = Find(map, key);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag ? *flag : fallback;
}

int64_t Integer(const Map& map, const char* key, int64_t fallback) {
  const auto* value = Find(map, key);
  if (!value) return fallback;
  if (const auto* narrow = std::get_if<int32_t>(value)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(value)) return *wide;
  return fallback;
}

const std::string* String(const Map& map, const char* key) {
  const auto* value = Find(map, key);
  return value ? std::get_if<std::string>(value) : nullptr;
}

}  // namespace

// static
void WebviewWindowPlugin::RegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()
                      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<WebviewWindowPlugin>(windows->messenger()));
}

WebviewWindowPlugin::WebviewWindowPlugin(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<Value>>(
          messenger, "desktop_webview_window",
          &flutter::StandardMethodCodec::GetInstance())),
      windows_() {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

WebviewWindowPlugin::~WebviewWindowPlugin() {
  channel_->SetMethodCallHandler(nullptr);
  lifetime_.reset();
  // Close windows while the engine is still alive.
  auto windows = std::move(windows_);
  for (const auto& entry : windows) {
    entry.second->Close();
  }
  windows.clear();
}

void WebviewWindowPlugin::Emit(const std::string& method, Map args) {
  channel_->InvokeMethod(method, std::make_unique<Value>(std::move(args)));
}

void WebviewWindowPlugin::Create(const Map& arguments,
                                 std::unique_ptr<Result> result) {
  if (!IsWebViewRuntimeAvailable()) {
    result->Error("webview_unavailable", "WebView2 runtime is not available");
    return;
  }
  WebviewWindow::Options options;
  const auto* title = String(arguments, "title");
  options.title = utf8_to_wide(title ? *title : std::string());
  options.width = static_cast<int>(Integer(arguments, "windowWidth", 1280));
  options.height = static_cast<int>(Integer(arguments, "windowHeight", 720));
  options.x = static_cast<int>(Integer(arguments, "windowPosX", 0));
  options.y = static_cast<int>(Integer(arguments, "windowPosY", 0));
  options.use_position = Bool(arguments, "useWindowPositionAndSize", false);
  options.open_maximized = Bool(arguments, "openMaximized", false);
  options.open_hidden = Bool(arguments, "openHidden", false);
  options.title_bar =
      static_cast<uint32_t>(Integer(arguments, "titleBar", 0xF));
  options.deny_camera_and_microphone =
      Bool(arguments, "denyCameraAndMicrophone", false);
  const auto* user_data_folder = String(arguments, "userDataFolderWindows");
  options.user_data_folder = utf8_to_wide(
      user_data_folder ? *user_data_folder : std::string("webview_window_WebView2"));
  const auto* bridge = String(arguments, "javaScriptBridge");
  options.javascript_bridge = utf8_to_wide(bridge ? *bridge : std::string());
  if (const auto* composer_arguments = String(arguments, "composerArguments")) {
    options.composer_arguments = *composer_arguments;
  }

  const auto window_id = dww::NextBrowserId();
  std::weak_ptr<bool> lifetime = lifetime_;
  auto window = std::make_shared<WebviewWindow>(
      [this, lifetime](const std::string& method, Map args) {
        if (!lifetime.expired()) Emit(method, std::move(args));
      },
      [lifetime, window_id](const std::wstring& url) {
        return lifetime.expired() ||
               dww::DecideNavigation(window_id, wide_to_utf8(url));
      },
      window_id,
      [this, lifetime, window_id]() {
        if (!lifetime.expired()) {
          windows_.erase(window_id);
        }
      });
  // Store ownership first: window creation can fail synchronously or pump
  // native messages, including an early close.
  windows_.emplace(window_id, window);
  std::shared_ptr<Result> pending_result(std::move(result));
  std::weak_ptr<WebviewWindow> weak_window = window;
  window->CreateAndShow(
      options, [window_id, pending_result, weak_window](
                   WebviewWindow::CreateOutcome outcome, const std::string& error) {
        switch (outcome) {
          case WebviewWindow::CreateOutcome::kFailed:
            pending_result->Error("create_failed", error);
            return;
          case WebviewWindow::CreateOutcome::kClosed:
            // Closed before WebView2 was ready, possibly from a composer.
            pending_result->Success(Value(Map{
                {Value("id"), Value(window_id)},
                {Value("windowHandle"), Value(int64_t{0})},
                {Value("closed"), Value(true)},
            }));
            return;
          case WebviewWindow::CreateOutcome::kReady: {
            auto window = weak_window.lock();
            const auto handle =
                window ? reinterpret_cast<int64_t>(window->GetHwnd()) : 0;
            pending_result->Success(Value(Map{
                {Value("id"), Value(window_id)},
                {Value("windowHandle"), Value(handle)},
            }));
            return;
          }
        }
      });
}

void WebviewWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<Value>& method_call,
    std::unique_ptr<Result> result) {
  const auto& method = method_call.method_name();
  static const Map kEmpty;
  const auto* map = std::get_if<Map>(method_call.arguments());
  const Map& arguments = map ? *map : kEmpty;

  if (method == "create") {
    Create(arguments, std::move(result));
    return;
  }
  if (method == "isWebviewAvailable") {
    result->Success(Value(IsWebViewRuntimeAvailable()));
    return;
  }
  if (method == "clearAll") {
    // Closing erases map entries; iterate a snapshot.
    std::vector<std::shared_ptr<WebviewWindow>> local;
    for (const auto& entry : windows_) local.push_back(entry.second);
    for (const auto& window : local) window->Close();
    result->Success();
    return;
  }

  const int64_t window_id = Integer(arguments, "viewId", -1);
  const auto found = windows_.find(window_id);
  if (method == "close") {
    // Closing an already closed window is harmless, as on other platforms.
    if (found != windows_.end()) {
      auto window = found->second;
      window->Close();
    }
    result->Success();
    return;
  }
  if (found == windows_.end()) {
    result->Error("browser_closed",
                  "No open browser with id " + std::to_string(window_id));
    return;
  }
  auto window = found->second;
  if (method == "setBrightness") {
    window->SetBrightness(static_cast<int>(Integer(arguments, "brightness", -1)));
    result->Success();
    return;
  }
  const auto& web_view = window->GetWebView();
  if (web_view && method == "setUrlRequestEnabled") {
    web_view->SetUrlRequestEnabled(Bool(arguments, "enabled", false));
    result->Success();
    return;
  }
  if (!web_view) {
    result->Error("browser_not_ready", "The browser view is not ready.");
    return;
  }
  if (method == "launch") {
    const auto* url = String(arguments, "url");
    if (!url) {
      result->Error("invalid_argument", "url is required");
      return;
    }
    web_view->setTriggerOnUrlRequestedEvent(
        Bool(arguments, "triggerOnUrlRequestEvent", true));
    web_view->Navigate(utf8_to_wide(*url));
    result->Success();
  } else if (method == "addScriptToExecuteOnDocumentCreated") {
    const auto* script = String(arguments, "javaScript");
    if (!script) {
      result->Error("invalid_argument", "javaScript is required");
      return;
    }
    web_view->AddScriptToExecuteOnDocumentCreated(utf8_to_wide(*script));
    result->Success();
  } else if (method == "setApplicationNameForUserAgent") {
    const auto* name = String(arguments, "applicationName");
    if (!name) {
      result->Error("invalid_argument", "applicationName is required");
      return;
    }
    web_view->SetApplicationNameForUserAgent(utf8_to_wide(*name));
    result->Success();
  } else if (method == "back") {
    web_view->GoBack();
    result->Success();
  } else if (method == "forward") {
    web_view->GoForward();
    result->Success();
  } else if (method == "reload") {
    web_view->Reload();
    result->Success();
  } else if (method == "stop") {
    web_view->Stop();
    result->Success();
  } else if (method == "getAllCookies") {
    web_view->GetAllCookies(std::move(result));
  } else if (method == "evaluateJavaScript") {
    const auto* script = String(arguments, "javaScriptString");
    if (!script) {
      result->Error("invalid_argument", "javaScriptString is required");
      return;
    }
    web_view->ExecuteJavaScript(utf8_to_wide(*script), std::move(result));
  } else if (method == "postJavaScriptMessage") {
    const auto* message = String(arguments, "message");
    if (!message) {
      result->Error("invalid_argument", "message is required");
      return;
    }
    web_view->PostJavaScriptMessage(utf8_to_wide(*message), std::move(result));
  } else if (method == "openDevToolsWindow") {
    web_view->openDevToolsWindow();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

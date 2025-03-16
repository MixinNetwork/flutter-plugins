#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>

#include "multi_window_manager.h"
#include "window_options.h"

namespace
{

  const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map, const char* key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it == map.end()) {
      return nullptr;
    }
    return &(it->second);
  }

  void PrintEncodableValue(const flutter::EncodableValue& value, int indent = 0) {
    std::string indentStr(indent, ' ');
    std::visit([&](auto&& arg)
    {
      using T = std::decay_t<decltype(arg)>;
      if constexpr (std::is_same_v<T, std::nullptr_t>) {
        std::cout << indentStr << "null";
      } else if constexpr (std::is_same_v<T, bool>) {
        std::cout << indentStr << (arg ? "true" : "false");
      } else if constexpr (std::is_same_v<T, int32_t>) {
        std::cout << indentStr << arg;
      } else if constexpr (std::is_same_v<T, int64_t>) {
        std::cout << indentStr << arg;
      } else if constexpr (std::is_same_v<T, double>) {
        std::cout << indentStr << arg;
      } else if constexpr (std::is_same_v<T, std::string>) {
        std::cout << indentStr << "\"" << arg << "\"";
      } else if constexpr (std::is_same_v<T, flutter::EncodableList>) {
        std::cout << indentStr << "[\n";
        for (const auto& elem : arg) {
          PrintEncodableValue(elem, indent + 2);
          std::cout << "\n";
        }
        std::cout << indentStr << "]";
      } else if constexpr (std::is_same_v<T, flutter::EncodableMap>) {
        std::cout << indentStr << "{\n";
        for (const auto& pair : arg) {
          PrintEncodableValue(pair.first, indent + 2);
          std::cout << ": ";
          PrintEncodableValue(pair.second, indent + 2);
          std::cout << "\n";
        }
        std::cout << indentStr << "}";
      } else {
        std::cout << indentStr << "Unknown type";
      } }, value);
  }

  class DesktopMultiWindowPlugin : public flutter::Plugin {
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    DesktopMultiWindowPlugin();

    ~DesktopMultiWindowPlugin() override;

  private:
    void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  };

  // static
  void DesktopMultiWindowPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(registrar->messenger(), "mixin.one/flutter_multi_window", &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<DesktopMultiWindowPlugin>();

    channel->SetMethodCallHandler([plugin_pointer = plugin.get()](const auto& call, auto result)
    {
      plugin_pointer->HandleMethodCall(call, std::move(result));
    });
    registrar->AddPlugin(std::move(plugin));
  }

  DesktopMultiWindowPlugin::DesktopMultiWindowPlugin() = default;

  DesktopMultiWindowPlugin::~DesktopMultiWindowPlugin() = default;

  void DesktopMultiWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    // std::cout << "Method called: " << method_call.method_name() << std::endl;

    // if (method_call.arguments()) {
    //   std::cout << "Method call arguments:\n";
    //   PrintEncodableValue(*method_call.arguments());
    //   std::cout << "\n";
    // }

    if (method_call.method_name() == "createWindow") {
      // Default values.
      std::string stringArgs = "";
      WindowOptions options;

      // Check if the argument is a map.
      if (method_call.arguments() &&
        std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
        const auto& args_map = std::get<flutter::EncodableMap>(*method_call.arguments());

        // If a string "arguments" is provided in the map, extract it.
        auto argsIter = args_map.find(flutter::EncodableValue("arguments"));
        if (argsIter != args_map.end() && std::holds_alternative<std::string>(argsIter->second)) {
          stringArgs = std::get<std::string>(argsIter->second);
        }

        // If window "options" are provided in the map, parse them.
        auto optionsIter = args_map.find(flutter::EncodableValue("options"));
        if (optionsIter != args_map.end() &&
          std::holds_alternative<flutter::EncodableMap>(optionsIter->second)) {
          const auto& optsMap = std::get<flutter::EncodableMap>(optionsIter->second);

          // Look for the "windows" key in the options map.
          auto windowsIter = optsMap.find(flutter::EncodableValue("windows"));
          if (windowsIter != optsMap.end() &&
            std::holds_alternative<flutter::EncodableMap>(windowsIter->second)) {
            const auto& windows_map = std::get<flutter::EncodableMap>(windowsIter->second);
            options.Parse(windows_map);
            // options.Print();
          } else {
            std::cout << "Key 'windows' not found or is not a map." << std::endl;
          }
        } else {
          std::cout << "No 'options' key found in arguments or it is not a map." << std::endl;
        }
      } else if (method_call.arguments() &&
        std::holds_alternative<std::string>(*method_call.arguments())) {
        // If a simple string is passed instead of a map, use it as the arguments.
        stringArgs = std::get<std::string>(*method_call.arguments());
      }

      auto window_id = MultiWindowManager::Instance()->Create(stringArgs, options);
      result->Success(flutter::EncodableValue(window_id));
      return;
    } else if (method_call.method_name() == "show") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Show(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "hide") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Hide(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "close") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Close(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "setFrame") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();

      auto* null_or_devicePixelRatio = std::get_if<double>(ValueOrNull(*arguments, "devicePixelRatio"));
      double devicePixelRatio = 1.0;
      if (null_or_devicePixelRatio != nullptr) {
        devicePixelRatio = *null_or_devicePixelRatio;
      }

      auto* null_or_x = std::get_if<double>(ValueOrNull(*arguments, "left"));
      auto* null_or_y = std::get_if<double>(ValueOrNull(*arguments, "top"));
      auto* null_or_width = std::get_if<double>(ValueOrNull(*arguments, "width"));
      auto* null_or_height = std::get_if<double>(ValueOrNull(*arguments, "height"));

      int x = 0;
      int y = 0;
      int width = 0;
      int height = 0;
      UINT uFlags = NULL;

      if (null_or_x != nullptr && null_or_y != nullptr) {
        x = static_cast<int>(*null_or_x * devicePixelRatio);
        y = static_cast<int>(*null_or_y * devicePixelRatio);
      }
      if (null_or_width != nullptr && null_or_height != nullptr) {
        width = static_cast<int>(*null_or_width * devicePixelRatio);
        height = static_cast<int>(*null_or_height * devicePixelRatio);
      }

      if (null_or_x == nullptr || null_or_y == nullptr) {
        uFlags = SWP_NOMOVE;
      }
      if (null_or_width == nullptr || null_or_height == nullptr) {
        uFlags = SWP_NOSIZE;
      }

      MultiWindowManager::Instance()->SetFrame(window_id, x, y, width, height);
      result->Success();
      return;
    } else if (method_call.method_name() == "getFrame") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      double devicePixelRatio = std::get<double>(arguments->at(flutter::EncodableValue("devicePixelRatio")));
      auto frame = MultiWindowManager::Instance()->GetFrame(window_id, devicePixelRatio);
      result->Success(frame);
      return;
    } else if (method_call.method_name() == "center") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Center(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "setTitle") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto title = std::get<std::string>(arguments->at(flutter::EncodableValue("title")));
      MultiWindowManager::Instance()->SetTitle(window_id, title);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "isFocused") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_focused = MultiWindowManager::Instance()->IsFocused(window_id);
      result->Success(flutter::EncodableValue(is_focused));
      return;
    } else if (method_call.method_name() == "isFullScreen") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_full_screen = MultiWindowManager::Instance()->IsFullScreen(window_id);
      result->Success(flutter::EncodableValue(is_full_screen));
      return;
    } else if (method_call.method_name() == "isMaximized") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_maximized = MultiWindowManager::Instance()->IsMaximized(window_id);
      result->Success(flutter::EncodableValue(is_maximized));
      return;
    } else if (method_call.method_name() == "isMinimized") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_minimized = MultiWindowManager::Instance()->IsMinimized(window_id);
      result->Success(flutter::EncodableValue(is_minimized));
      return;
    } else if (method_call.method_name() == "isVisible") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_visible = MultiWindowManager::Instance()->IsVisible(window_id);
      result->Success(flutter::EncodableValue(is_visible));
      return;
    } else if (method_call.method_name() == "maximize") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      bool vertically = std::get<bool>(arguments->at(flutter::EncodableValue("vertically")));
      std::cout << "maximize: " << window_id << " " << vertically << std::endl;
      MultiWindowManager::Instance()->Maximize(window_id, vertically);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "unmaximize") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Unmaximize(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "minimize") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Minimize(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "restore") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      MultiWindowManager::Instance()->Restore(window_id);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "setFullScreen") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto is_full_screen = std::get<bool>(arguments->at(flutter::EncodableValue("isFullScreen")));
      MultiWindowManager::Instance()->SetFullScreen(window_id, is_full_screen);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "setStyle") {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto window_id = arguments->at(flutter::EncodableValue("windowId")).LongValue();
      auto style = std::get<int32_t>(arguments->at(flutter::EncodableValue("style")));
      auto extended_style = std::get<int32_t>(arguments->at(flutter::EncodableValue("extendedStyle")));
      MultiWindowManager::Instance()->SetStyle(window_id, style, extended_style);
      result->Success(flutter::EncodableValue(true));
      return;
    } else if (method_call.method_name() == "getAllSubWindowIds") {
      auto window_ids = MultiWindowManager::Instance()->GetAllSubWindowIds();
      result->Success(window_ids);
      return;
    }
    result->NotImplemented();
  }

} // namespace

void DesktopMultiWindowPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto registrar_windows = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  InternalMultiWindowPluginRegisterWithRegistrar(registrar);

  // Attach MainWindow for
  auto view = FlutterDesktopPluginRegistrarGetView(registrar);
  auto hwnd = FlutterDesktopViewGetHWND(view);
  
  auto inter_window_event_channel = InterWindowEventChannel::RegisterWithRegistrar(registrar, 0);
  auto window_events_channel = WindowEventsChannel::RegisterWithRegistrar(registrar);
  MultiWindowManager::Instance()->AttachFlutterMainWindow(
    GetAncestor(hwnd, GA_ROOT),
    std::move(inter_window_event_channel),
    std::move(window_events_channel),
    registrar_windows
  );
}

void InternalMultiWindowPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  DesktopMultiWindowPlugin::RegisterWithRegistrar(flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

#include "flutter_view.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cassert>
#include <cstring>


namespace webview_window {
namespace {

// Exact ABI from Flutter 3.47.6's shell/platform/windows/
// flutter_windows_internal.h. The exported function creates a controller with
// owns_engine=false. FlutterDesktopViewControllerCreate is NOT interchangeable:
// it transfers engine ownership and would tear down every sibling toolbar.
struct BorrowedViewControllerProperties {
  int width;
  int height;
};
using CreateBorrowedViewController = FlutterDesktopViewControllerRef (*)(
    FlutterDesktopEngineRef, const BorrowedViewControllerProperties*);

CreateBorrowedViewController BorrowedCreateFunction(FARPROC symbol) {
  CreateBorrowedViewController create = nullptr;
  static_assert(sizeof(create) == sizeof(symbol), "Windows function pointer ABI changed");
  std::memcpy(&create, &symbol, sizeof(create));
  return create;
}

}  // namespace

TitleBarViews::TitleBarViews(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "desktop_webview_window/titlebars",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "initialize") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      const auto found = args ? args->find(flutter::EncodableValue("engineId")) :
          flutter::EncodableMap::const_iterator{};
      if (!args || found == args->end() ||
          (!std::holds_alternative<int32_t>(found->second) &&
           !std::holds_alternative<int64_t>(found->second))) {
        result->Error("titlebar_engine_missing", "The application engine ID is required.");
        return;
      }
      std::string error;
      if (!Initialize(found->second.LongValue(), &error)) {
        result->Error("titlebar_multiview_unavailable", error);
      } else {
        const auto main_view = args->find(flutter::EncodableValue("mainViewId"));
        result->Success(main_view == args->end() ? flutter::EncodableValue(int64_t{0}) : main_view->second);
      }
    } else if (call.method_name() == "getViews") {
      result->Success(flutter::EncodableValue(GetViews()));
    } else {
      result->NotImplemented();
    }
  });
}

bool TitleBarViews::Initialize(int64_t engine_id, std::string* error) {
  if (engine_) return true;
  auto module = GetModuleHandleW(L"flutter_windows.dll");
  create_view_controller_ = module ? GetProcAddress(
      module, "FlutterDesktopEngineCreateViewController") : nullptr;
  FARPROC engine_for_id_symbol = module ? GetProcAddress(
      module, "FlutterDesktopEngineForId") : nullptr;
  if (!create_view_controller_ || !engine_for_id_symbol) {
    *error = "Titlebars require a Windows engine exporting "
             "FlutterDesktopEngineCreateViewController and FlutterDesktopEngineForId.";
    return false;
  }
  using EngineForId = FlutterDesktopEngineRef (*)(int64_t);
  EngineForId engine_for_id = nullptr;
  static_assert(sizeof(engine_for_id) == sizeof(engine_for_id_symbol));
  std::memcpy(&engine_for_id, &engine_for_id_symbol, sizeof(engine_for_id));
  engine_ = engine_for_id(engine_id);
  return engine_ != nullptr;
}

TitleBarViews::~TitleBarViews() {
  assert(views_.empty());
  channel_->SetMethodCallHandler(nullptr);
  // The runner owns the engine and its main view. Never destroy either here.
}

std::unique_ptr<FlutterView> TitleBarViews::CreateView(
    int64_t web_view_id, int top_padding, int width, int height,
    std::string* error) {
  if (!engine_) {
    *error = "Mount WebviewWindowApp before creating a titlebar.";
    return nullptr;
  }
  BorrowedViewControllerProperties properties = {width, height};
  auto controller = BorrowedCreateFunction(create_view_controller_)(engine_, &properties);
  if (!controller) {
    *error = "Failed to create a view on the shared title bar Flutter engine.";
    return nullptr;
  }
  auto view = FlutterDesktopViewControllerGetView(controller);
  if (!view || !FlutterDesktopViewGetHWND(view)) {
    FlutterDesktopViewControllerDestroy(controller);
    *error = "The shared title bar Flutter view has no native window.";
    return nullptr;
  }
  const int64_t view_id = FlutterDesktopViewControllerGetViewId(controller);
  auto result = std::unique_ptr<FlutterView>(new FlutterView(this, controller, view_id));
  // Flutter view IDs are engine-assigned; browser IDs live in a separate space.
  // Register before notifying Dart, including when the first snapshot raced Run.
  views_.emplace(view_id, flutter::EncodableMap{
      {flutter::EncodableValue("viewId"), flutter::EncodableValue(view_id)},
      {flutter::EncodableValue("webViewId"), flutter::EncodableValue(web_view_id)},
      {flutter::EncodableValue("titleBarTopPadding"), flutter::EncodableValue(top_padding)},
  });
  NotifyViewsChanged();
  return result;
}

void TitleBarViews::RemoveView(int64_t view_id) {
  views_.erase(view_id);
  NotifyViewsChanged();
}

flutter::EncodableList TitleBarViews::GetViews() const {
  flutter::EncodableList result;
  for (const auto& entry : views_) {
    result.emplace_back(entry.second);
  }
  return result;
}

void TitleBarViews::NotifyViewsChanged() {
  channel_->InvokeMethod("viewsChanged", nullptr);
}

void TitleBarViews::ReloadSystemFonts() {
  FlutterDesktopEngineReloadSystemFonts(engine_);
}

FlutterView::FlutterView(TitleBarViews* owner,
                         FlutterDesktopViewControllerRef controller, int64_t view_id)
    : owner_(owner), controller_(controller), view_id_(view_id) {}

FlutterView::~FlutterView() {
  // Withdraw the routing record before the engine sends its view-removal metrics.
  owner_->RemoveView(view_id_);
  FlutterDesktopViewControllerDestroy(controller_);
}

HWND FlutterView::GetWindow() const {
  return FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(controller_));
}

std::optional<LRESULT> FlutterView::HandleTopLevelWindowProc(
    HWND hwnd, UINT message, WPARAM w_param, LPARAM l_param) {
  LRESULT result;
  if (FlutterDesktopViewControllerHandleTopLevelWindowProc(
          controller_, hwnd, message, w_param, l_param, &result)) {
    return result;
  }
  return std::nullopt;
}

void FlutterView::ReloadSystemFonts() {
  owner_->ReloadSystemFonts();
}

void FlutterView::ForceRedraw() {
  FlutterDesktopViewControllerForceRedraw(controller_);
}

}  // namespace webview_window

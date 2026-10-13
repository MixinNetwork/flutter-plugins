#include "flutter_view.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cassert>
#include <cstring>

#include "message_channel_plugin.h"

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

bool SharedToolbarEngine::Initialize(std::string* error) {
  if (engine_) {
    return true;
  }
  auto module = GetModuleHandleW(L"flutter_windows.dll");
  create_view_controller_ = module ? GetProcAddress(
      module, "FlutterDesktopEngineCreateViewController") : nullptr;
  if (!create_view_controller_) {
    *error = "Shared title bars require Flutter 3.47.6 or a compatible Windows "
             "engine exporting FlutterDesktopEngineCreateViewController.";
    return false;
  }

  const char* arguments[] = {"web_view_title_bar", "shared"};
  FlutterDesktopEngineProperties properties = {};
  // Match DartProject(L"data"); the C API resolves these against the executable.
  properties.assets_path = L"data\\flutter_assets";
  properties.icu_data_path = L"data\\icudtl.dat";
  properties.aot_library_path = L"data\\app.so";
  properties.dart_entrypoint_argc = 2;
  properties.dart_entrypoint_argv = arguments;
  engine_ = FlutterDesktopEngineCreate(&properties);
  if (!engine_) {
    *error = "Failed to create the shared title bar Flutter engine.";
    return false;
  }

  auto registrar = FlutterDesktopEngineGetPluginRegistrar(
      engine_, "DesktopWebviewWindowToolbarPlugin");
  auto registrar_windows = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  // Install both channels before the first view starts the Dart entrypoint.
  RegisterClientMessageChannelPlugin(registrar);
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar_windows->messenger(), "desktop_webview_window/titlebars",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "getViews") {
      result->Success(flutter::EncodableValue(GetViews()));
    } else if (call.method_name() == "ready") {
      result->Success();
      NotifyViewsChanged();
    } else {
      result->NotImplemented();
    }
  });

  // Stock Windows Flutter treats view 0 as permanent and never removes it from
  // the engine/framework. Reserve it here so closing the first browser cannot
  // leave Flutter presenting to a destroyed implicit view.
  const BorrowedViewControllerProperties implicit_properties = {0, 0};
  implicit_controller_ = BorrowedCreateFunction(create_view_controller_)(
      engine_, &implicit_properties);
  if (!implicit_controller_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
    FlutterDesktopEngineDestroy(engine_);
    engine_ = nullptr;
    *error = "Failed to start the shared title bar Flutter engine.";
    return false;
  }
  ShowWindow(FlutterDesktopViewGetHWND(
      FlutterDesktopViewControllerGetView(implicit_controller_)), SW_HIDE);
  return true;
}

SharedToolbarEngine::~SharedToolbarEngine() {
  // WebviewWindowPlugin destroys all borrowed views before its engine owner.
  assert(views_.empty());
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  if (implicit_controller_) {
    FlutterDesktopViewControllerDestroy(implicit_controller_);
  }
  if (engine_) {
    FlutterDesktopEngineDestroy(engine_);
  }
}

std::unique_ptr<FlutterView> SharedToolbarEngine::CreateView(
    int64_t web_view_id, int top_padding, int width, int height,
    std::string* error) {
  if (!Initialize(error)) {
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

void SharedToolbarEngine::RemoveView(int64_t view_id) {
  views_.erase(view_id);
  NotifyViewsChanged();
}

flutter::EncodableList SharedToolbarEngine::GetViews() const {
  flutter::EncodableList result;
  for (const auto& entry : views_) {
    result.emplace_back(entry.second);
  }
  return result;
}

void SharedToolbarEngine::NotifyViewsChanged() {
  channel_->InvokeMethod("viewsChanged", nullptr);
}

void SharedToolbarEngine::ReloadSystemFonts() {
  FlutterDesktopEngineReloadSystemFonts(engine_);
}

FlutterView::FlutterView(SharedToolbarEngine* owner,
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

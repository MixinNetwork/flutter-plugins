//
// Created by yangbin on 2022/1/11.
//

#include "flutter_window.h"

#include "tchar.h"

#include <iostream>
#include <utility>

#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

namespace {

  WindowCreatedCallback _g_window_created_callback = nullptr;

  TCHAR kFlutterWindowClassName[] = _T("FlutterMultiWindow");

  int32_t class_registered_ = 0;

  void RegisterWindowClass(WNDPROC wnd_proc) {
    if (class_registered_ == 0) {
      WNDCLASS window_class{};
      window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
      window_class.lpszClassName = kFlutterWindowClassName;
      window_class.style = CS_HREDRAW | CS_VREDRAW;
      window_class.cbClsExtra = 0;
      window_class.cbWndExtra = 0;
      window_class.hInstance = GetModuleHandle(nullptr);
      window_class.hIcon =
        LoadIcon(window_class.hInstance, IDI_APPLICATION);
      window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
      window_class.lpszMenuName = nullptr;
      window_class.lpfnWndProc = wnd_proc;
      RegisterClass(&window_class);
    }
    class_registered_++;
  }

  void UnregisterWindowClass() {
    class_registered_--;
    if (class_registered_ != 0) {
      return;
    }
    UnregisterClass(kFlutterWindowClassName, nullptr);
  }

  // Scale helper to convert logical scaler values to physical using passed in
  // scale factor
  inline int Scale(int source, double scale_factor) {
    return static_cast<int>(source * scale_factor);
  }

  using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

  // Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
  // This API is only needed for PerMonitor V1 awareness mode.
  void EnableFullDpiSupportIfAvailable(HWND hwnd) {
    HMODULE user32_module = LoadLibraryA("User32.dll");
    if (!user32_module) {
      return;
    }
    auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
        GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
    if (enable_non_client_dpi_scaling != nullptr) {
      enable_non_client_dpi_scaling(hwnd);
      FreeLibrary(user32_module);
    }
  }
}

FlutterWindow::FlutterWindow(
  int64_t id,
  std::string args,
  const std::shared_ptr<BaseFlutterWindowCallback>& callback,
  WindowOptions options
) {
  callback_ = callback;
  id_ = id;
  window_handle_ = nullptr;
  scale_factor_ = 1;

  RegisterWindowClass(FlutterWindow::WndProc);

  const POINT target_point = { static_cast<LONG>(10),
                              static_cast<LONG>(10) };
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  scale_factor_ = dpi / 96.0;

  // Create the window using CreateWindowEx with the provided extended style.
  // If no extended style is desired, options.exStyle can be 0.
  HWND window_handle = CreateWindowEx(
    options.exStyle,             // Extended window style
    kFlutterWindowClassName,     // Window class name
    options.title.c_str(),       // Window title (wide string)
    options.style,               // Window style
    Scale(options.left, scale_factor_),
    Scale(options.top, scale_factor_),
    Scale(options.width, scale_factor_),
    Scale(options.height, scale_factor_),
    nullptr,                   // Parent window handle
    nullptr,                   // Menu handle
    GetModuleHandle(nullptr),  // Instance handle
    this);                     // Additional application data

  RECT frame;
  GetClientRect(window_handle, &frame);
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({ "multi_window", std::to_string(id), std::move(args) });
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
    frame.right - frame.left, frame.bottom - frame.top, project);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
  }
  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetParent(view_handle, window_handle);
  MoveWindow(view_handle, 0, 0, frame.right - frame.left, frame.bottom - frame.top, true);

  auto registrar_plugin = flutter_controller_->engine()->GetRegistrarForPlugin("DesktopMultiWindowPlugin");
  registrar_ = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_plugin);

  InternalMultiWindowPluginRegisterWithRegistrar(registrar_plugin);
  inter_window_event_channel_ = InterWindowEventChannel::RegisterWithRegistrar(registrar_plugin, id_);
  window_events_channel_ = WindowEventsChannel::RegisterWithRegistrar(registrar_plugin);

  if (_g_window_created_callback) {
    _g_window_created_callback(flutter_controller_.get());
  }

  SetBackgroundColor(options.backgroundColor);

  // hide the window when created.
  ShowWindow(window_handle, SW_HIDE);

}

// static
FlutterWindow* FlutterWindow::GetThisFromHandle(HWND window) noexcept {
  return reinterpret_cast<FlutterWindow*>(
    GetWindowLongPtr(window, GWLP_USERDATA));
}

// static
LRESULT CALLBACK FlutterWindow::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<FlutterWindow*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (FlutterWindow* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

FlutterWindow::~FlutterWindow() {
  if (window_handle_) {
    std::cout << "window_handle leak." << std::endl;
  }
  UnregisterWindowClass();
}

void DesktopMultiWindowSetWindowCreatedCallback(WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}

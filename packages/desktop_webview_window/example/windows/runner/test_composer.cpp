#include "test_composer.h"

#include <desktop_webview_window/webview_window_composer.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kSidebarClass[] = L"TestComposerSidebar";
constexpr int kSidebarWidth = 48;

struct Handled {
  std::string mode;
  HWND view = nullptr;
  HWND sidebar = nullptr;
};

std::map<int64_t, Handled> handled;
// "<browser>:<callback>" in delivery order.
std::vector<std::string> events;

void Record(int64_t browser, const char* event) {
  events.push_back(std::to_string(browser) + ":" + event);
}

// The sidebar is the application's own window: the browser window's
// procedure belongs to the plugin, so button commands arrive here.
LRESULT CALLBACK SidebarProc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == WM_COMMAND) {
    const auto browser =
        static_cast<int64_t>(GetWindowLongPtr(window, GWLP_USERDATA));
    switch (LOWORD(wparam)) {
      case 1:
        dww_browser_go_back(browser);
        break;
      case 2:
        dww_browser_go_forward(browser);
        break;
      case 3:
        dww_browser_reload(browser);
        break;
    }
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

HWND CreateSidebar(HWND parent, int64_t browser) {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = SidebarProc;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    window_class.lpszClassName = kSidebarClass;
    RegisterClassW(&window_class);
    registered = true;
  }
  HWND sidebar = CreateWindowExW(0, kSidebarClass, L"", WS_CHILD | WS_VISIBLE,
                                 0, 0, 0, 0, parent, nullptr,
                                 GetModuleHandle(nullptr), nullptr);
  SetWindowLongPtr(sidebar, GWLP_USERDATA, static_cast<LONG_PTR>(browser));
  const wchar_t* labels[] = {L"<", L">", L"R"};
  for (int i = 0; i < 3; i++) {
    CreateWindowExW(0, L"BUTTON", labels[i], WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                    4, 8 + i * 44, 40, 40, sidebar,
                    reinterpret_cast<HMENU>(static_cast<INT_PTR>(i + 1)),
                    GetModuleHandle(nullptr), nullptr);
  }
  return sidebar;
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  Record(request->browser, "compose");
  if (request->arguments == nullptr) return DWW_COMPOSE_DEFAULT;
  Handled entry;
  entry.mode = request->arguments;
  entry.view = static_cast<HWND>(request->webview_view);
  if (entry.mode == "minimize:compose") {
    // Compose precedes WebView::Create: WM_SIZE must tolerate a null controller.
    ShowWindow(static_cast<HWND>(request->window), SW_MINIMIZE);
    Record(request->browser, IsIconic(static_cast<HWND>(request->window))
                                 ? "minimized-before-create"
                                 : "minimize-failed");
  }
  if (entry.mode == "close:initializing") {
    struct PendingClose {
      HWND window;
      int64_t browser;
    };
    static std::map<UINT_PTR, PendingClose> pending;
    const UINT_PTR timer = SetTimer(
        nullptr, 0, 1,
        [](HWND, UINT, UINT_PTR id, DWORD) {
          KillTimer(nullptr, id);
          const auto found = pending.find(id);
          if (found == pending.end()) return;
          const auto target = found->second;
          pending.erase(found);
          if (IsWindow(target.window)) {
            Record(target.browser, "native-close-during-create");
            SendMessage(target.window, WM_CLOSE, 0, 0);
          }
        });
    pending[timer] = {static_cast<HWND>(request->window), request->browser};
  }
  if (entry.mode == "close:compose") {
    handled[request->browser] = entry;
    Record(request->browser, dww_browser_close(request->browser)
                                 ? "close-accepted"
                                 : "close-ignored");
    return DWW_COMPOSE_HANDLED;
  }
  if (entry.mode == "sidebar") {
    entry.sidebar =
        CreateSidebar(static_cast<HWND>(request->window), request->browser);
  }
  handled[request->browser] = entry;
  // Other modes have no layout of their own; the WebView fills the window.
  return DWW_COMPOSE_HANDLED;
}

void Layout(void*, int64_t browser, int32_t width, int32_t height) {
  const auto found = handled.find(browser);
  if (found == handled.end()) return;
  const Handled& entry = found->second;
  const int left = entry.sidebar
                       ? MulDiv(kSidebarWidth, GetDpiForWindow(entry.view), 96)
                       : 0;
  if (entry.sidebar) MoveWindow(entry.sidebar, 0, 0, left, height, TRUE);
  MoveWindow(entry.view, left, 0, (std::max)(0, width - left), height, TRUE);
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  Record(state->browser, "navigation");
  const auto found = handled.find(state->browser);
  if (found == handled.end()) return;
  // Close once a page has finished loading.
  if (found->second.mode == "close:navigation" && state->url != nullptr &&
      !state->is_loading) {
    Record(state->browser, dww_browser_close(state->browser)
                               ? "close-accepted"
                               : "close-ignored");
  }
}

void Closing(void*, int64_t browser) {
  Record(browser, "closing");
  const auto found = handled.find(browser);
  if (found != handled.end() && found->second.mode == "close:closing") {
    Record(browser,
           dww_browser_close(browser) ? "close-accepted" : "close-ignored");
  }
  handled.erase(browser);
}

HWND FindChild(HWND root, const wchar_t* class_name) {
  struct Search {
    const wchar_t* class_name;
    HWND found;
  } search{class_name, nullptr};
  EnumChildWindows(
      root,
      [](HWND child, LPARAM data) -> BOOL {
        auto* search = reinterpret_cast<Search*>(data);
        wchar_t name[64];
        GetClassNameW(child, name, 64);
        if (wcscmp(name, search->class_name) == 0) {
          search->found = child;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  return search.found;
}

// Buttons in reading order: left to right, then top to bottom.
std::vector<HWND> Buttons(HWND root) {
  std::vector<HWND> buttons;
  EnumChildWindows(
      root,
      [](HWND child, LPARAM data) -> BOOL {
        wchar_t name[16];
        GetClassNameW(child, name, 16);
        if (_wcsicmp(name, L"Button") == 0) {
          reinterpret_cast<std::vector<HWND>*>(data)->push_back(child);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&buttons));
  std::sort(buttons.begin(), buttons.end(), [](HWND a, HWND b) {
    RECT ra, rb;
    GetWindowRect(a, &ra);
    GetWindowRect(b, &rb);
    return ra.left != rb.left ? ra.left < rb.left : ra.top < rb.top;
  });
  return buttons;
}

// A clickable control: a child button, or a button the window draws in its
// own title bar, found by hit testing above the WebView.
struct Control {
  HWND button;
  POINT point;
};

// Title bar buttons, then child buttons.
std::vector<Control> Controls(HWND window, HWND web) {
  std::vector<Control> controls;
  RECT client, rect;
  GetClientRect(window, &client);
  GetWindowRect(web, &rect);
  MapWindowPoints(HWND_DESKTOP, window, reinterpret_cast<POINT*>(&rect), 2);
  // Below the top resize border.
  const LONG y = rect.top * 2 / 3;
  LONG start = -1;
  for (LONG x = 0; rect.top > 0 && x <= client.right; x++) {
    POINT screen{x, y};
    ClientToScreen(window, &screen);
    const bool hit =
        x < client.right &&
        SendMessage(window, WM_NCHITTEST, 0,
                    MAKELPARAM(static_cast<SHORT>(screen.x),
                               static_cast<SHORT>(screen.y))) == HTCLIENT;
    if (hit && start < 0) start = x;
    if (!hit && start >= 0) {
      controls.push_back({nullptr, {(start + x) / 2, y}});
      start = -1;
    }
  }
  for (HWND button : Buttons(window)) controls.push_back({button, {}});
  return controls;
}

std::string WindowTitle(HWND window) {
  std::wstring wide(GetWindowTextLengthW(window) + 1, L'\0');
  wide.resize(GetWindowTextW(window, wide.data(), static_cast<int>(wide.size())));
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                       static_cast<int>(wide.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string utf8(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

int64_t IntArgument(const EncodableMap& args, const char* key) {
  const auto found = args.find(EncodableValue(key));
  if (found == args.end()) return 0;
  if (const auto* narrow = std::get_if<int32_t>(&found->second)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(&found->second)) return *wide;
  return 0;
}

}  // namespace

void TestComposerInstall() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged, Layout,
                                    Closing};
  dww_set_composer(&composer);
}

void TestComposerRegisterChannel(flutter::BinaryMessenger* messenger) {
  // Kept alive for the engine's lifetime.
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "webview_example/native_test",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "composerEvents") {
      EncodableList list;
      for (const auto& event : events) list.emplace_back(event);
      result->Success(EncodableValue(list));
      return;
    }
    if (method == "clearComposerEvents") {
      events.clear();
      result->Success();
      return;
    }
    static const EncodableMap kEmpty;
    const auto* map = std::get_if<EncodableMap>(call.arguments());
    const EncodableMap& args = map ? *map : kEmpty;
    auto window = reinterpret_cast<HWND>(IntArgument(args, "handle"));
    if (!window || !IsWindow(window)) {
      result->Error("no_window", "Unknown window");
      return;
    }
    if (method == "windowTitle") {
      result->Success(EncodableValue(WindowTitle(window)));
      return;
    }
    if (method == "nativeClose") {
      SendMessage(window, WM_CLOSE, 0, 0);
      result->Success();
      return;
    }
    if (method == "restore") {
      ShowWindow(window, SW_RESTORE);
      result->Success();
      return;
    }
    HWND web = FindChild(window, L"web_view_window_web_view");
    if (method == "hostErasePixel" && web) {
      BITMAPINFO info{};
      info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = 1;
      info.bmiHeader.biHeight = -1;
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      void* pixels = nullptr;
      HDC dc = CreateCompatibleDC(nullptr);
      HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
      HGDIOBJ previous = SelectObject(dc, bitmap);
      SendMessage(web, WM_ERASEBKGND, reinterpret_cast<WPARAM>(dc), 0);
      const COLORREF color = GetPixel(dc, 0, 0);
      SelectObject(dc, previous);
      DeleteObject(bitmap);
      DeleteDC(dc);
      result->Success(EncodableValue(EncodableList{
          EncodableValue(GetRValue(color) / 255.0),
          EncodableValue(GetGValue(color) / 255.0),
          EncodableValue(GetBValue(color) / 255.0)}));
      return;
    }
    if (method == "geometry") {
      if (!web) {
        result->Error("no_webview", "No WebView");
        return;
      }
      RECT client, rect;
      GetClientRect(window, &client);
      GetWindowRect(web, &rect);
      MapWindowPoints(HWND_DESKTOP, window, reinterpret_cast<POINT*>(&rect), 2);
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("contentWidth"), EncodableValue(int32_t(client.right))},
          {EncodableValue("contentHeight"), EncodableValue(int32_t(client.bottom))},
          {EncodableValue("webX"), EncodableValue(int32_t(rect.left))},
          {EncodableValue("webY"), EncodableValue(int32_t(rect.top))},
          {EncodableValue("webWidth"), EncodableValue(int32_t(rect.right - rect.left))},
          {EncodableValue("webHeight"), EncodableValue(int32_t(rect.bottom - rect.top))},
          {EncodableValue("buttons"),
           EncodableValue(int32_t(Controls(window, web).size()))},
      }));
      return;
    }
    if (method == "resize") {
      // Client size in physical pixels.
      RECT frame{0, 0, static_cast<LONG>(IntArgument(args, "width")),
                 static_cast<LONG>(IntArgument(args, "height"))};
      AdjustWindowRectExForDpi(&frame, GetWindowLong(window, GWL_STYLE), FALSE,
                               GetWindowLong(window, GWL_EXSTYLE),
                               GetDpiForWindow(window));
      SetWindowPos(window, nullptr, 0, 0, frame.right - frame.left,
                   frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER);
      result->Success();
      return;
    }
    if (method == "clickButton") {
      const auto controls =
          web ? Controls(window, web) : std::vector<Control>();
      const auto index = IntArgument(args, "index");
      if (index < 0 || index >= static_cast<int64_t>(controls.size())) {
        result->Error("no_button", "No such button");
        return;
      }
      const Control& control = controls[index];
      if (control.button) {
        SendMessage(control.button, BM_CLICK, 0, 0);
      } else {
        const LPARAM point = MAKELPARAM(control.point.x, control.point.y);
        SendMessage(window, WM_LBUTTONDOWN, MK_LBUTTON, point);
        SendMessage(window, WM_LBUTTONUP, 0, point);
      }
      result->Success();
      return;
    }
    result->NotImplemented();
  });
}

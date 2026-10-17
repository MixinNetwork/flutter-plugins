// The default composer: an icon-only toolbar above the WebView, drawn with
// GDI. It uses only the public composer API.

#include <windows.h>

#include <algorithm>
#include <map>
#include <memory>
#include <string>

#include "composer_runtime.h"
#include "strconv.h"

namespace {

constexpr wchar_t kToolbarClass[] = L"DesktopWebviewToolbar";
constexpr int kToolbarHeight = 36;
enum Command { kBack = 1, kForward, kReload };

struct Toolbar {
  int64_t browser = 0;
  HWND view = nullptr;
  HWND window = nullptr;  // Null when the toolbar is hidden.
  HWND buttons[3] = {};
  bool can_go_back = false;
  bool can_go_forward = false;
  bool loading = false;
  std::wstring title;
};

std::map<int64_t, std::unique_ptr<Toolbar>>& Toolbars() {
  static auto* toolbars = new std::map<int64_t, std::unique_ptr<Toolbar>>();
  return *toolbars;
}

double ScaleFor(HWND window) { return GetDpiForWindow(window) / 96.0; }

bool IsDark(HWND window) {
  // Set by Webview.setBrightness; otherwise follow the system app theme.
  const auto pinned = reinterpret_cast<INT_PTR>(
      GetPropW(GetAncestor(window, GA_ROOT), L"DesktopWebviewDark"));
  if (pinned != 0) return pinned == 1;
  DWORD light = 1;
  DWORD size = sizeof(light);
  RegGetValueW(HKEY_CURRENT_USER,
               L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
               L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  return light == 0;
}

HFONT CreateUiFont(const wchar_t* face, int logical_size, double scale) {
  return CreateFontW(-static_cast<int>(logical_size * scale), 0, 0, 0, FW_NORMAL,
                     FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                     CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, face);
}

void DrawButton(const Toolbar& toolbar, const DRAWITEMSTRUCT& item) {
  const bool dark = IsDark(item.hwndItem);
  const COLORREF background = dark ? RGB(32, 32, 32) : RGB(243, 243, 243);
  const bool enabled = !(item.itemState & ODS_DISABLED);
  const bool pressed = item.itemState & ODS_SELECTED;
  HBRUSH brush = CreateSolidBrush(
      pressed ? (dark ? RGB(56, 56, 56) : RGB(224, 224, 224)) : background);
  FillRect(item.hDC, &item.rcItem, brush);
  DeleteObject(brush);
  // Segoe MDL2 Assets: Back, Forward, Refresh, Cancel.
  const wchar_t* glyph = item.CtlID == kBack      ? L"\uE72B"
                         : item.CtlID == kForward ? L"\uE72A"
                         : toolbar.loading        ? L"\uE711"
                                                  : L"\uE72C";
  HFONT font = CreateUiFont(L"Segoe MDL2 Assets", 12, ScaleFor(item.hwndItem));
  HGDIOBJ previous = SelectObject(item.hDC, font);
  SetBkMode(item.hDC, TRANSPARENT);
  SetTextColor(item.hDC, !enabled  ? RGB(128, 128, 128)
                         : dark    ? RGB(255, 255, 255)
                                   : RGB(0, 0, 0));
  RECT rect = item.rcItem;
  DrawTextW(item.hDC, glyph, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(item.hDC, previous);
  DeleteObject(font);
}

void Paint(Toolbar& toolbar, HWND window) {
  PAINTSTRUCT paint;
  HDC dc = BeginPaint(window, &paint);
  RECT bounds;
  GetClientRect(window, &bounds);
  const bool dark = IsDark(window);
  const double scale = ScaleFor(window);
  HBRUSH background = CreateSolidBrush(dark ? RGB(32, 32, 32) : RGB(243, 243, 243));
  FillRect(dc, &bounds, background);
  DeleteObject(background);
  RECT separator = bounds;
  separator.top = separator.bottom - 1;
  HBRUSH line = CreateSolidBrush(dark ? RGB(64, 64, 64) : RGB(218, 218, 218));
  FillRect(dc, &separator, line);
  DeleteObject(line);

  HFONT font = CreateUiFont(L"Segoe UI", 13, scale);
  HGDIOBJ previous = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, dark ? RGB(200, 200, 200) : RGB(64, 64, 64));
  RECT text = bounds;
  text.left = static_cast<LONG>((3 * kToolbarHeight + 10) * scale);
  text.right -= static_cast<LONG>(8 * scale);
  DrawTextW(dc, toolbar.title.c_str(), -1, &text,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(dc, previous);
  DeleteObject(font);
  EndPaint(window, &paint);
}

LRESULT CALLBACK ToolbarProc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  auto* toolbar =
      reinterpret_cast<Toolbar*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (toolbar == nullptr) return DefWindowProc(window, message, wparam, lparam);
  switch (message) {
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kBack:
          dww_browser_go_back(toolbar->browser);
          break;
        case kForward:
          dww_browser_go_forward(toolbar->browser);
          break;
        case kReload:
          if (toolbar->loading) {
            dww_browser_stop(toolbar->browser);
          } else {
            dww_browser_reload(toolbar->browser);
          }
          break;
      }
      return 0;
    case WM_DRAWITEM:
      DrawButton(*toolbar, *reinterpret_cast<DRAWITEMSTRUCT*>(lparam));
      return TRUE;
    case WM_SIZE: {
      const int size = static_cast<int>(kToolbarHeight * ScaleFor(window));
      for (int i = 0; i < 3; i++) {
        MoveWindow(toolbar->buttons[i], i * size, 0, size, size - 1, TRUE);
      }
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      Paint(*toolbar, window);
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void RegisterToolbarClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = ToolbarProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kToolbarClass;
  RegisterClassW(&window_class);
  registered = true;
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  auto toolbar = std::make_unique<Toolbar>();
  toolbar->browser = request->browser;
  toolbar->view = static_cast<HWND>(request->webview_view);
  if (request->show_toolbar) {
    RegisterToolbarClass();
    auto* parent = static_cast<HWND>(request->window);
    toolbar->window = CreateWindowExW(
        0, kToolbarClass, L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN, 0, 0, 0,
        0, parent, nullptr, GetModuleHandle(nullptr), nullptr);
    for (int i = 0; i < 3; i++) {
      toolbar->buttons[i] = CreateWindowExW(
          0, L"BUTTON", L"", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0,
          toolbar->window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBack + i)),
          GetModuleHandle(nullptr), nullptr);
    }
    EnableWindow(toolbar->buttons[0], FALSE);
    EnableWindow(toolbar->buttons[1], FALSE);
    SetWindowLongPtr(toolbar->window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(toolbar.get()));
  }
  Toolbars()[request->browser] = std::move(toolbar);
  return DWW_COMPOSE_HANDLED;
}

void Layout(void*, int64_t browser, int32_t width, int32_t height) {
  const auto found = Toolbars().find(browser);
  if (found == Toolbars().end()) return;
  Toolbar& toolbar = *found->second;
  const int top = toolbar.window
                      ? static_cast<int>(kToolbarHeight * ScaleFor(toolbar.view))
                      : 0;
  if (toolbar.window) MoveWindow(toolbar.window, 0, 0, width, top, TRUE);
  MoveWindow(toolbar.view, 0, top, width, (std::max)(0, height - top), TRUE);
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  const auto found = Toolbars().find(state->browser);
  if (found == Toolbars().end() || !found->second->window) return;
  Toolbar& toolbar = *found->second;
  toolbar.can_go_back = state->can_go_back;
  toolbar.can_go_forward = state->can_go_forward;
  toolbar.loading = state->is_loading;
  toolbar.title = state->title ? utf8_to_wide(state->title) : std::wstring();
  EnableWindow(toolbar.buttons[0], toolbar.can_go_back);
  EnableWindow(toolbar.buttons[1], toolbar.can_go_forward);
  RedrawWindow(toolbar.window, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN);
}

void Closing(void*, int64_t browser) {
  const auto found = Toolbars().find(browser);
  if (found == Toolbars().end()) return;
  // The windows are destroyed with the browser window.
  if (found->second->window) {
    SetWindowLongPtr(found->second->window, GWLP_USERDATA, 0);
  }
  Toolbars().erase(found);
}

}  // namespace

namespace dww {

const DWWComposer& DefaultComposer() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged, Layout,
                                    Closing};
  return composer;
}

}  // namespace dww

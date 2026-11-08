// The default composer: navigation buttons, the page title and its host in
// the window's title bar, the WebView below. It uses only the public composer
// API.
//
// The title bar is the top of the client area and is painted opaque, like
// Chrome's custom-drawn frame: DWM keeps the side and bottom borders and the
// shadow, and this composer draws the minimize, maximize and close buttons
// itself so they fill the taller bar. They report HTMINBUTTON, HTMAXBUTTON
// and HTCLOSE so Windows 11 still offers Snap Layouts.

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <uxtheme.h>
#include <windowsx.h>

#include <algorithm>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "composer_runtime.h"
#include "strconv.h"
#include "title_bar_accessibility.h"
#include "utils.h"

namespace {

constexpr UINT_PTR kSubclassId = 1;
constexpr int kButtonWidth = 40;
constexpr int kButtonGap = 2;
constexpr int kPadding = 4;
constexpr int kTextGap = 8;
constexpr int kCornerRadius = 4;
constexpr int kBarHeight = 40;
constexpr int kCaptionButtonWidth = 46;
// The Windows 11 title bar colors without Mica, and its close button hover.
constexpr COLORREF kBarBackgroundLight = RGB(243, 243, 243);
constexpr COLORREF kBarBackgroundDark = RGB(32, 32, 32);
constexpr COLORREF kCloseHovered = RGB(196, 43, 28);
// Posted by UI Automation to run a button, with its index.
const UINT kInvokeMessage = RegisterWindowMessageW(L"DesktopWebviewTitleBarInvoke");

// Navigation commands first, then the caption buttons from left to right.
enum class Command { kBack, kForward, kReload, kMinimize, kMaximize, kClose };

bool IsCaption(Command command) { return command >= Command::kMinimize; }

struct TitleBar {
  int64_t browser = 0;
  HWND window = nullptr;
  HWND view = nullptr;
  uint32_t items = 0;
  std::vector<Command> commands;
  // CreateConfiguration.title, shown while the page has no title.
  std::wstring fallback_title;
  std::wstring title;
  std::wstring host;
  bool can_go_back = false;
  bool can_go_forward = false;
  bool loading = false;
  bool active = true;
  int hot = -1;
  int pressed = -1;
  bool tracking = false;
  bool nc_tracking = false;
  HWND tooltip = nullptr;
  std::unique_ptr<dww::TitleBarAccessibility> accessibility;

  bool Has(DWWTitleBarItem item) const { return items & item; }

  int NavigationCount() const {
    return static_cast<int>(std::count_if(
        commands.begin(), commands.end(),
        [](Command command) { return !IsCaption(command); }));
  }

  bool Enabled(Command command) const {
    switch (command) {
      case Command::kBack:
        return can_go_back;
      case Command::kForward:
        return can_go_forward;
      default:
        return true;
    }
  }
};

std::map<int64_t, std::unique_ptr<TitleBar>>& TitleBars() {
  static auto* title_bars = new std::map<int64_t, std::unique_ptr<TitleBar>>();
  return *title_bars;
}

// Tooltip and accessible name.
const wchar_t* Label(const TitleBar& bar, Command command) {
  switch (command) {
    case Command::kBack:
      return L"Back";
    case Command::kForward:
      return L"Forward";
    case Command::kReload:
      return bar.loading ? L"Stop" : L"Reload";
    case Command::kMinimize:
      return L"Minimize";
    case Command::kMaximize:
      return IsZoomed(bar.window) ? L"Restore Down" : L"Maximize";
    case Command::kClose:
      return L"Close";
  }
  return L"";
}

const wchar_t* AutomationId(Command command) {
  switch (command) {
    case Command::kBack:
      return L"Back";
    case Command::kForward:
      return L"Forward";
    case Command::kReload:
      return L"Reload";
    case Command::kMinimize:
      return L"Minimize";
    case Command::kMaximize:
      return L"Maximize";
    case Command::kClose:
      return L"Close";
  }
  return L"";
}

bool IsHighContrast() {
  HIGHCONTRASTW contrast{sizeof(contrast)};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast,
                               0) &&
         (contrast.dwFlags & HCF_HIGHCONTRASTON);
}

// Windows 11 draws the top window border itself; Windows 10 leaves it to
// windows without a top frame.
bool IsWindows11() {
  static const bool windows11 = [] {
    using RtlGetVersion = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    const auto get_version = reinterpret_cast<RtlGetVersion>(
        GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
    RTL_OSVERSIONINFOW info{sizeof(info)};
    return get_version && get_version(&info) == 0 &&
           info.dwBuildNumber >= 22000;
  }();
  return windows11;
}

bool IsDark(HWND window) {
  // Set by Webview.setBrightness; otherwise follow the system app theme.
  const auto pinned =
      reinterpret_cast<INT_PTR>(GetPropW(window, L"DesktopWebviewDark"));
  if (pinned != 0) return pinned == 1;
  DWORD light = 1;
  DWORD size = sizeof(light);
  RegGetValueW(HKEY_CURRENT_USER,
               L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
               L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  return light == 0;
}

int Scaled(HWND window, int logical) {
  return MulDiv(logical, static_cast<int>(GetDpiForWindow(window)), 96);
}

// Vertical extent of the title bar in client coordinates. The top resize
// border of a restored window lies inside it.
struct Band {
  int resize;  // Rows that resize the window instead.
  int bottom;  // Height of the title bar.
};

int FrameHeight(HWND window) {
  const UINT dpi = GetDpiForWindow(window);
  return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

Band BandOf(HWND window) {
  // A maximized window's client area already starts below its frame.
  const int resize =
      IsZoomed(window)
          ? 0
          : GetSystemMetricsForDpi(SM_CYSIZEFRAME, GetDpiForWindow(window));
  return {resize, Scaled(window, kBarHeight)};
}

// Left edge of the caption buttons in client coordinates.
int CaptionButtonsLeft(HWND window) {
  RECT client;
  GetClientRect(window, &client);
  return client.right - 3 * Scaled(window, kCaptionButtonWidth);
}

RECT ButtonRect(const TitleBar& bar, int index) {
  const Band band = BandOf(bar.window);
  const Command command = bar.commands[index];
  if (IsCaption(command)) {
    // Full height, like Chrome's: a maximized window's buttons reach the
    // screen edge.
    const int width = Scaled(bar.window, kCaptionButtonWidth);
    const int left = CaptionButtonsLeft(bar.window) +
                     (static_cast<int>(command) -
                      static_cast<int>(Command::kMinimize)) *
                         width;
    return {left, 0, left + width, band.bottom};
  }
  const int width = Scaled(bar.window, kButtonWidth);
  const int left = Scaled(bar.window, kPadding) +
                   index * (width + Scaled(bar.window, kButtonGap));
  const int inset = Scaled(bar.window, kPadding);
  // Navigation gives way to the caption buttons in a narrow window.
  if (left + width > CaptionButtonsLeft(bar.window)) return {};
  return {left, inset, left + width, band.bottom - inset};
}

// Right edge of the visible navigation buttons, or 0.
int NavigationRight(const TitleBar& bar) {
  int right = 0;
  for (int i = 0; i < bar.NavigationCount(); i++) {
    right = (std::max)(right, static_cast<int>(ButtonRect(bar, i).right));
  }
  return right;
}

int ButtonAt(const TitleBar& bar, POINT point) {
  for (int i = 0; i < static_cast<int>(bar.commands.size()); i++) {
    const RECT rect = ButtonRect(bar, i);
    if (PtInRect(&rect, point)) return i;
  }
  return -1;
}

// The button under the cursor, for leave notifications that carry no point.
int ButtonAtCursor(const TitleBar& bar) {
  POINT point;
  GetCursorPos(&point);
  if (WindowFromPoint(point) != bar.window) return -1;
  ScreenToClient(bar.window, &point);
  return ButtonAt(bar, point);
}

void InvalidateBar(const TitleBar& bar) {
  RECT rect;
  GetClientRect(bar.window, &rect);
  rect.bottom = BandOf(bar.window).bottom;
  InvalidateRect(bar.window, &rect, FALSE);
}

const wchar_t* IconFontFace() {
  static const wchar_t* face = [] {
    LOGFONTW query{};
    query.lfCharSet = DEFAULT_CHARSET;
    wcscpy_s(query.lfFaceName, L"Segoe Fluent Icons");
    bool found = false;
    HDC dc = GetDC(nullptr);
    EnumFontFamiliesExW(
        dc, &query,
        [](const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM found) -> int {
          *reinterpret_cast<bool*>(found) = true;
          return 0;
        },
        reinterpret_cast<LPARAM>(&found), 0);
    ReleaseDC(nullptr, dc);
    // Windows 11 icons, falling back to the Windows 10 font.
    return found ? L"Segoe Fluent Icons" : L"Segoe MDL2 Assets";
  }();
  return face;
}

// Blends |color| at |alpha| over a rounded rectangle of the opaque paint
// buffer. |rect| is in client coordinates and may extend past the buffer.
void FillHighlight(HPAINTBUFFER buffer, const RECT& rect, COLORREF color,
                   BYTE alpha, int radius) {
  RGBQUAD* bits = nullptr;
  int row = 0;
  RECT target;
  RECT area;
  if (FAILED(GetBufferedPaintBits(buffer, &bits, &row)) ||
      FAILED(GetBufferedPaintTargetRect(buffer, &target)) ||
      !IntersectRect(&area, &rect, &target)) {
    return;
  }
  const auto blend = [alpha](BYTE source, BYTE target) {
    return static_cast<BYTE>((source * alpha + target * (255 - alpha)) / 255);
  };
  for (LONG y = area.top; y < area.bottom; y++) {
    for (LONG x = area.left; x < area.right; x++) {
      const LONG dx = (std::max)({rect.left + radius - 1 - x, 0L,
                                  x - (rect.right - radius)});
      const LONG dy = (std::max)({rect.top + radius - 1 - y, 0L,
                                  y - (rect.bottom - radius)});
      if (dx * dx + dy * dy > radius * radius) continue;
      RGBQUAD& pixel = bits[(y - target.top) * row + (x - target.left)];
      pixel = {blend(GetBValue(color), pixel.rgbBlue),
               blend(GetGValue(color), pixel.rgbGreen),
               blend(GetRValue(color), pixel.rgbRed), 255};
    }
  }
}

// Draws antialiased text over the bar. DrawThemeTextEx derives coverage
// from the contrast with the transparent buffer, which loses dark text, so
// the text is drawn white into its own buffer, tinted, and blended.
void DrawLabel(HDC dc, HTHEME theme, const std::wstring& text, RECT rect,
               COLORREF color, DWORD format) {
  if (rect.right <= rect.left || rect.bottom <= rect.top) return;
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  BP_PAINTPARAMS params{sizeof(params), BPPF_ERASE, nullptr, &blend};
  HDC label_dc = nullptr;
  HPAINTBUFFER label = BeginBufferedPaint(dc, &rect, BPBF_TOPDOWNDIB, &params,
                                          &label_dc);
  if (!label) return;
  HGDIOBJ previous = SelectObject(label_dc, GetCurrentObject(dc, OBJ_FONT));
  DTTOPTS options{sizeof(options)};
  options.dwFlags = DTT_COMPOSITED | DTT_TEXTCOLOR;
  options.crText = RGB(255, 255, 255);
  DrawThemeTextEx(theme, label_dc, 0, 0, text.c_str(), -1,
                  format | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX, &rect,
                  &options);
  SelectObject(label_dc, previous);
  RGBQUAD* bits = nullptr;
  int row = 0;
  if (SUCCEEDED(GetBufferedPaintBits(label, &bits, &row))) {
    for (LONG y = 0; y < rect.bottom - rect.top; y++) {
      for (LONG x = 0; x < rect.right - rect.left; x++) {
        RGBQUAD& pixel = bits[y * row + x];
        const int alpha = pixel.rgbReserved;
        pixel.rgbRed = static_cast<BYTE>(GetRValue(color) * alpha / 255);
        pixel.rgbGreen = static_cast<BYTE>(GetGValue(color) * alpha / 255);
        pixel.rgbBlue = static_cast<BYTE>(GetBValue(color) * alpha / 255);
      }
    }
  }
  EndBufferedPaint(label, TRUE);
}

struct Palette {
  COLORREF background;  // Of the title bar.
  COLORREF content;     // Below the title bar, until the WebView covers it.
  COLORREF primary;
  COLORREF secondary;
  COLORREF disabled;
  // Hovered and pressed buttons: |highlight| blended at the alphas, with the
  // glyph in |highlight_text|.
  COLORREF highlight;
  COLORREF highlight_text;
  BYTE hover_alpha;
  BYTE pressed_alpha;
  COLORREF close;
  COLORREF close_text;
  BYTE close_pressed_alpha;
};

Palette PaletteOf(const TitleBar& bar) {
  if (IsHighContrast()) {
    // The user's contrast theme: caption colors, with the system highlight
    // for hovered and pressed buttons.
    const COLORREF text =
        GetSysColor(bar.active ? COLOR_CAPTIONTEXT : COLOR_INACTIVECAPTIONTEXT);
    const COLORREF highlight = GetSysColor(COLOR_HIGHLIGHT);
    return {GetSysColor(bar.active ? COLOR_ACTIVECAPTION : COLOR_INACTIVECAPTION),
            GetSysColor(COLOR_WINDOW),
            text,
            text,
            GetSysColor(COLOR_GRAYTEXT),
            highlight,
            GetSysColor(COLOR_HIGHLIGHTTEXT),
            0xFF,
            0xFF,
            highlight,
            GetSysColor(COLOR_HIGHLIGHTTEXT),
            0xFF};
  }
  const bool dark = IsDark(bar.window);
  const COLORREF primary = !bar.active ? (dark ? RGB(150, 150, 150) : RGB(120, 120, 120))
                           : dark      ? RGB(255, 255, 255)
                                       : RGB(0, 0, 0);
  // Chrome's caption button colors, which match the native buttons.
  return {dark ? kBarBackgroundDark : kBarBackgroundLight,
          webview_window::ContentBackgroundColor(dark),
          primary,
          !bar.active ? primary : dark ? RGB(180, 180, 180) : RGB(96, 96, 96),
          dark ? RGB(110, 110, 110) : RGB(160, 160, 160),
          dark ? RGB(255, 255, 255) : RGB(0, 0, 0),
          primary,
          0x1A,
          0x33,
          kCloseHovered,
          RGB(255, 255, 255),
          0x98};
}

// Draws the top window border of a restored Windows 10 window, which has no
// top frame for DWM to draw it in. Colors follow Chrome's.
void DrawTopBorder(const TitleBar& bar, HPAINTBUFFER buffer) {
  if (IsWindows11() || IsZoomed(bar.window)) return;
  COLORREF color;
  BYTE alpha = 0xFF;
  DWORD prevalence = 0;
  DWORD size = sizeof(prevalence);
  DWORD colorization = 0;
  BOOL opaque = FALSE;
  if (IsHighContrast()) {
    color = GetSysColor(bar.active ? COLOR_ACTIVEBORDER : COLOR_INACTIVEBORDER);
  } else if (!bar.active) {
    color = RGB(0x55, 0x55, 0x55);
    alpha = 0x80;
  } else if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\DWM",
                          L"ColorPrevalence", RRF_RT_REG_DWORD, nullptr,
                          &prevalence, &size) == ERROR_SUCCESS &&
             prevalence == 1 &&
             SUCCEEDED(DwmGetColorizationColor(&colorization, &opaque))) {
    // "Show accent color on title bars and window borders".
    color = RGB(colorization >> 16 & 0xFF, colorization >> 8 & 0xFF,
                colorization & 0xFF);
  } else {
    color = RGB(0x26, 0x26, 0x26);
    alpha = 0xA8;
  }
  RECT client;
  GetClientRect(bar.window, &client);
  // Whole pixels, like Chrome's.
  client.bottom =
      (std::max)(1, static_cast<int>(GetDpiForWindow(bar.window)) / 96);
  FillHighlight(buffer, client, color, alpha, 0);
}

void DrawBar(const TitleBar& bar, HDC dc, HPAINTBUFFER buffer) {
  HWND window = bar.window;
  const Palette palette = PaletteOf(bar);
  const COLORREF primary = palette.primary;
  const COLORREF secondary = palette.secondary;
  const COLORREF disabled = palette.disabled;
  HTHEME theme = OpenThemeData(window, L"CompositedWindow::Window");

  // Buttons: Segoe icons for Back, Forward, Refresh and Cancel.
  HFONT icons = CreateFontW(-Scaled(window, 14), 0, 0, 0, FW_NORMAL, FALSE,
                            FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                            DEFAULT_PITCH, IconFontFace());
  HGDIOBJ previous = SelectObject(dc, icons);
  HFONT caption_icons = CreateFontW(
      -Scaled(window, 10), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, IconFontFace());
  for (int i = 0; i < static_cast<int>(bar.commands.size()); i++) {
    const Command command = bar.commands[i];
    const bool enabled = bar.Enabled(command);
    const RECT rect = ButtonRect(bar, i);
    // Pressed shows only while the pointer stays on the button.
    const bool pressed = i == bar.pressed && i == bar.hot;
    const bool hot = i == bar.hot && (bar.pressed < 0 || pressed);
    COLORREF color = enabled ? primary : disabled;
    if (IsCaption(command)) {
      if (command == Command::kClose && (hot || pressed)) {
        FillHighlight(buffer, rect, palette.close,
                      pressed ? palette.close_pressed_alpha : 0xFF, 0);
        color = palette.close_text;
      } else if (hot || pressed) {
        FillHighlight(buffer, rect, palette.highlight,
                      pressed ? palette.pressed_alpha : palette.hover_alpha, 0);
        color = palette.highlight_text;
      }
      const wchar_t* glyph = command == Command::kMinimize ? L"\uE921"
                             : command == Command::kClose  ? L"\uE8BB"
                             : IsZoomed(window)            ? L"\uE923"
                                                           : L"\uE922";
      SelectObject(dc, caption_icons);
      DrawLabel(dc, theme, glyph, rect, color, DT_CENTER);
      continue;
    }
    if (enabled && (hot || pressed)) {
      FillHighlight(buffer, rect, palette.highlight,
                    pressed ? palette.pressed_alpha : palette.hover_alpha,
                    Scaled(window, kCornerRadius));
      color = palette.highlight_text;
    }
    const wchar_t* glyph = command == Command::kBack      ? L"\uE72B"
                           : command == Command::kForward ? L"\uE72A"
                           : bar.loading                  ? L"\uE711"
                                                          : L"\uE72C";
    SelectObject(dc, icons);
    DrawLabel(dc, theme, glyph, rect, color, DT_CENTER);
  }

  // Title and host, left of the caption buttons. The host keeps up to half
  // the space; the title is truncated first.
  NONCLIENTMETRICSW metrics{sizeof(metrics)};
  SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics,
                             0, GetDpiForWindow(window));
  HFONT caption = CreateFontIndirectW(&metrics.lfCaptionFont);
  SelectObject(dc, caption);
  const bool show_title = bar.Has(DWW_TITLE_BAR_TITLE);
  const bool show_host = bar.Has(DWW_TITLE_BAR_HOST) && !bar.host.empty();
  const Band band = BandOf(window);
  const int navigation_right = NavigationRight(bar);
  RECT text{navigation_right == 0
                ? Scaled(window, 12)
                : navigation_right + Scaled(window, kTextGap),
            band.resize, CaptionButtonsLeft(window) - Scaled(window, kTextGap),
            band.bottom};
  if (show_title && show_host) {
    const std::wstring& title = bar.title;
    SIZE title_size{}, host_size{};
    GetTextExtentPoint32W(dc, title.c_str(), static_cast<int>(title.size()),
                          &title_size);
    GetTextExtentPoint32W(dc, bar.host.c_str(),
                          static_cast<int>(bar.host.size()), &host_size);
    const LONG available = text.right - text.left;
    const LONG gap = Scaled(window, kTextGap);
    const LONG host_width = (std::min)(host_size.cx, available / 2);
    const LONG title_width =
        (std::max)(0L, (std::min)(title_size.cx, available - gap - host_width));
    RECT title_rect = text;
    title_rect.right = text.left + title_width;
    DrawLabel(dc, theme, title, title_rect, primary, DT_LEFT | DT_END_ELLIPSIS);
    RECT host_rect = text;
    host_rect.left = title_rect.right + gap;
    DrawLabel(dc, theme, bar.host, host_rect, secondary,
             DT_LEFT | DT_END_ELLIPSIS);
  } else if (show_title || show_host) {
    DrawLabel(dc, theme, show_title ? bar.title : bar.host, text, primary,
             DT_LEFT | DT_END_ELLIPSIS);
  }
  SelectObject(dc, previous);
  DeleteObject(caption);
  DeleteObject(caption_icons);
  DeleteObject(icons);
  if (theme) CloseThemeData(theme);
}

void Paint(const TitleBar& bar) {
  PAINTSTRUCT paint;
  HDC dc = BeginPaint(bar.window, &paint);
  RECT client;
  GetClientRect(bar.window, &client);
  RECT top = client;
  top.bottom = BandOf(bar.window).bottom;
  // Below the title bar, until the WebView covers it.
  RECT below = client;
  below.top = top.bottom;
  const Palette palette = PaletteOf(bar);
  HBRUSH background = CreateSolidBrush(palette.content);
  FillRect(dc, &below, background);
  DeleteObject(background);
  BP_PAINTPARAMS params{sizeof(params), BPPF_ERASE};
  HDC buffer_dc = nullptr;
  HPAINTBUFFER buffer = BeginBufferedPaint(dc, &top, BPBF_TOPDOWNDIB, &params,
                                           &buffer_dc);
  if (buffer) {
    HBRUSH bar_background = CreateSolidBrush(palette.background);
    FillRect(buffer_dc, &top, bar_background);
    DeleteObject(bar_background);
    // FillRect leaves the alpha channel clear; the bar is opaque.
    BufferedPaintSetAlpha(buffer, &top, 255);
    DrawBar(bar, buffer_dc, buffer);
    DrawTopBorder(bar, buffer);
    EndBufferedPaint(buffer, TRUE);
  }
  EndPaint(bar.window, &paint);
}

void Run(const TitleBar& bar, Command command) {
  switch (command) {
    case Command::kBack:
      dww_browser_go_back(bar.browser);
      break;
    case Command::kForward:
      dww_browser_go_forward(bar.browser);
      break;
    case Command::kReload:
      if (bar.loading) {
        dww_browser_stop(bar.browser);
      } else {
        dww_browser_reload(bar.browser);
      }
      break;
    // Posted: closing can destroy the window and remove this subclass.
    case Command::kMinimize:
      PostMessageW(bar.window, WM_SYSCOMMAND, SC_MINIMIZE, 0);
      break;
    case Command::kMaximize:
      PostMessageW(bar.window, WM_SYSCOMMAND,
                   IsZoomed(bar.window) ? SC_RESTORE : SC_MAXIMIZE, 0);
      break;
    case Command::kClose:
      PostMessageW(bar.window, WM_SYSCOMMAND, SC_CLOSE, 0);
      break;
  }
}

LRESULT HitCode(Command command) {
  switch (command) {
    case Command::kMinimize:
      return HTMINBUTTON;
    case Command::kMaximize:
      return HTMAXBUTTON;
    case Command::kClose:
      return HTCLOSE;
    default:
      return HTCLIENT;
  }
}

bool IsCaptionHit(WPARAM hit) {
  return hit == HTMINBUTTON || hit == HTMAXBUTTON || hit == HTCLOSE;
}

void SetHot(TitleBar& bar, int hot) {
  if (hot == bar.hot) return;
  bar.hot = hot;
  InvalidateBar(bar);
}

void Press(TitleBar& bar, int index) {
  if (index < 0 || !bar.Enabled(bar.commands[index])) return;
  bar.pressed = index;
  bar.hot = index;
  // Delivers the release as WM_LBUTTONUP, also for the caption buttons.
  SetCapture(bar.window);
  InvalidateBar(bar);
}

// Feeds a mouse message in client coordinates to the tooltip, which then
// also hides when the pointer moves on to the caption buttons.
void RelayToTooltip(const TitleBar& bar, UINT message, POINT point) {
  if (!bar.tooltip) return;
  MSG msg{bar.window, message, 0, MAKELPARAM(point.x, point.y)};
  msg.time = GetMessageTime();
  GetCursorPos(&msg.pt);
  SendMessageW(bar.tooltip, TTM_RELAYEVENT, 0, reinterpret_cast<LPARAM>(&msg));
}

void UpdateTooltips(const TitleBar& bar) {
  if (!bar.tooltip) return;
  for (int i = 0; i < bar.NavigationCount(); i++) {
    TTTOOLINFOW tool{TTTOOLINFOW_V2_SIZE};
    tool.hwnd = bar.window;
    tool.uId = i;
    tool.rect = ButtonRect(bar, i);
    SendMessageW(bar.tooltip, TTM_NEWTOOLRECTW, 0,
                 reinterpret_cast<LPARAM>(&tool));
  }
}

void CreateTooltip(TitleBar& bar) {
  INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_BAR_CLASSES};
  InitCommonControlsEx(&controls);
  bar.tooltip = CreateWindowExW(
      WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr,
      WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX, CW_USEDEFAULT, CW_USEDEFAULT,
      CW_USEDEFAULT, CW_USEDEFAULT, bar.window, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (!bar.tooltip) return;
  // Navigation buttons only: Windows shows its own tooltips for the caption
  // buttons, as they report HTMINBUTTON, HTMAXBUTTON and HTCLOSE.
  for (int i = 0; i < bar.NavigationCount(); i++) {
    // The text is requested through TTN_GETDISPINFO as it follows the state.
    TTTOOLINFOW tool{TTTOOLINFOW_V2_SIZE};
    tool.hwnd = bar.window;
    tool.uId = i;
    tool.rect = ButtonRect(bar, i);
    tool.lpszText = LPSTR_TEXTCALLBACKW;
    SendMessageW(bar.tooltip, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
  }
}

std::vector<dww::AccessibleButton> AccessibleButtons(const TitleBar& bar) {
  std::vector<dww::AccessibleButton> buttons;
  for (int i = 0; i < static_cast<int>(bar.commands.size()); i++) {
    const Command command = bar.commands[i];
    buttons.push_back({AutomationId(command), Label(bar, command),
                       bar.Enabled(command), ButtonRect(bar, i)});
  }
  return buttons;
}

LRESULT HitTest(const TitleBar& bar, WPARAM wparam, LPARAM lparam) {
  // Side and bottom borders keep their default handling.
  const LRESULT hit = DefSubclassProc(bar.window, WM_NCHITTEST, wparam, lparam);
  if (hit != HTCLIENT) return hit;
  POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ScreenToClient(bar.window, &point);
  const Band band = BandOf(bar.window);
  if (point.y < band.resize) {
    const int corner = Scaled(bar.window, 16);
    RECT client;
    GetClientRect(bar.window, &client);
    if (point.x < corner) return HTTOPLEFT;
    if (point.x >= client.right - corner) return HTTOPRIGHT;
    return HTTOP;
  }
  if (point.y < band.bottom) {
    // Caption buttons report their system codes, which Windows 11 needs for
    // Snap Layouts; the navigation buttons are client area.
    const int index = ButtonAt(bar, point);
    return index >= 0 ? HitCode(bar.commands[index]) : HTCAPTION;
  }
  return HTCLIENT;
}

LRESULT CALLBACK TitleBarProc(HWND window, UINT message, WPARAM wparam,
                              LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  auto& bar = *reinterpret_cast<TitleBar*>(data);
  LRESULT result = 0;
  if (message == kInvokeMessage) {
    const auto index = static_cast<size_t>(wparam);
    if (index < bar.commands.size() && bar.Enabled(bar.commands[index])) {
      Run(bar, bar.commands[index]);
    }
    return 0;
  }
  switch (message) {
    case WM_NCCALCSIZE: {
      if (!wparam) break;
      // Keep the default side and bottom borders; the client area takes the
      // caption and the top border.
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG top = params->rgrc[0].top;
      result = DefSubclassProc(window, message, wparam, lparam);
      params->rgrc[0].top = top;
      // A maximized window extends past the monitor by its frame.
      if (IsZoomed(window)) params->rgrc[0].top += FrameHeight(window);
      return result;
    }
    case WM_NCHITTEST:
      return HitTest(bar, wparam, lparam);
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      Paint(bar);
      return 0;
    case WM_NCACTIVATE:
      bar.active = wparam != FALSE;
      InvalidateBar(bar);
      break;
    case WM_MOUSEMOVE: {
      if (!bar.tracking) {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window};
        bar.tracking = TrackMouseEvent(&track);
      }
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RelayToTooltip(bar, message, point);
      SetHot(bar, ButtonAt(bar, point));
      return 0;
    }
    case WM_MOUSELEAVE:
      bar.tracking = false;
      SetHot(bar, ButtonAtCursor(bar));
      return 0;
    case WM_NCMOUSEMOVE: {
      if (!bar.nc_tracking) {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE | TME_NONCLIENT, window};
        bar.nc_tracking = TrackMouseEvent(&track);
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      RelayToTooltip(bar, WM_MOUSEMOVE, point);
      SetHot(bar, IsCaptionHit(wparam) ? ButtonAt(bar, point) : -1);
      // DefWindowProc shows Snap Layouts over HTMAXBUTTON.
      break;
    }
    case WM_NCMOUSELEAVE:
      bar.nc_tracking = false;
      SetHot(bar, ButtonAtCursor(bar));
      break;
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      // DefWindowProc would draw classic caption buttons over the bar and
      // run the command itself, so the bar handles caption buttons alone.
      if (IsCaptionHit(wparam)) {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ScreenToClient(window, &point);
        RelayToTooltip(bar, WM_LBUTTONDOWN, point);
        Press(bar, ButtonAt(bar, point));
        return 0;
      }
      break;
    case WM_NCLBUTTONUP:
    case WM_NCRBUTTONDOWN:
    case WM_NCRBUTTONUP:
      if (IsCaptionHit(wparam)) return 0;
      break;
    case WM_LBUTTONDOWN: {
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RelayToTooltip(bar, message, point);
      Press(bar, ButtonAt(bar, point));
      return 0;
    }
    case WM_LBUTTONUP: {
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RelayToTooltip(bar, message, point);
      const int pressed = bar.pressed;
      if (pressed < 0) return 0;
      const int index = ButtonAt(bar, point);
      // Releases capture and clears pressed through WM_CAPTURECHANGED.
      ReleaseCapture();
      bar.pressed = -1;
      InvalidateBar(bar);
      // Last: the command can close the browser and remove this subclass.
      if (index == pressed) Run(bar, bar.commands[index]);
      return 0;
    }
    case WM_CAPTURECHANGED:
      if (bar.pressed >= 0) {
        bar.pressed = -1;
        InvalidateBar(bar);
      }
      break;
    case WM_NOTIFY: {
      auto* header = reinterpret_cast<NMHDR*>(lparam);
      if (header->hwndFrom == bar.tooltip && header->code == TTN_GETDISPINFOW) {
        const auto index = static_cast<size_t>(header->idFrom);
        if (index < bar.commands.size()) {
          reinterpret_cast<NMTTDISPINFOW*>(lparam)->lpszText =
              const_cast<wchar_t*>(Label(bar, bar.commands[index]));
        }
        return 0;
      }
      break;
    }
    case WM_GETOBJECT:
      if (bar.accessibility &&
          bar.accessibility->HandleGetObject(wparam, lparam, &result)) {
        return result;
      }
      break;
    case WM_GETMINMAXINFO: {
      // Keep room for the caption buttons.
      result = DefSubclassProc(window, message, wparam, lparam);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      RECT frame{0, 0, 3 * Scaled(window, kCaptionButtonWidth), 0};
      AdjustWindowRectExForDpi(&frame,
                               static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE)),
                               FALSE, 0, GetDpiForWindow(window));
      info->ptMinTrackSize.x =
          (std::max)(info->ptMinTrackSize.x, frame.right - frame.left);
      return result;
    }
    case WM_SETTINGCHANGE:
    case WM_SYSCOLORCHANGE:
    case WM_THEMECHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      InvalidateBar(bar);
      break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  static const bool buffered_paint = SUCCEEDED(BufferedPaintInit());
  (void)buffered_paint;
  auto title_bar = std::make_unique<TitleBar>();
  TitleBar* bar = title_bar.get();
  bar->browser = request->browser;
  bar->window = static_cast<HWND>(request->window);
  bar->view = static_cast<HWND>(request->webview_view);
  bar->items = request->title_bar;
  if (bar->Has(DWW_TITLE_BAR_NAVIGATION)) {
    bar->commands = {Command::kBack, Command::kForward};
  }
  if (bar->Has(DWW_TITLE_BAR_RELOAD)) bar->commands.push_back(Command::kReload);
  bar->commands.insert(bar->commands.end(), {Command::kMinimize,
                                             Command::kMaximize,
                                             Command::kClose});
  bar->fallback_title.resize(GetWindowTextLengthW(bar->window) + 1);
  bar->fallback_title.resize(GetWindowTextW(
      bar->window, bar->fallback_title.data(),
      static_cast<int>(bar->fallback_title.size())));
  bar->title = bar->fallback_title;
  TitleBars()[request->browser] = std::move(title_bar);
  CreateTooltip(*bar);
  bar->accessibility = std::make_unique<dww::TitleBarAccessibility>(
      bar->window, [bar] { return AccessibleButtons(*bar); },
      [window = bar->window](int index) {
        PostMessageW(window, kInvokeMessage, static_cast<WPARAM>(index), 0);
      });

  SetWindowSubclass(bar->window, TitleBarProc, kSubclassId,
                    reinterpret_cast<DWORD_PTR>(bar));
  // Recompute the frame with the subclass in place.
  SetWindowPos(bar->window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  return DWW_COMPOSE_HANDLED;
}

void Layout(void*, int64_t browser, int32_t width, int32_t height) {
  const auto found = TitleBars().find(browser);
  if (found == TitleBars().end()) return;
  const TitleBar& bar = *found->second;
  const int top = BandOf(bar.window).bottom;
  MoveWindow(bar.view, 0, top, width, (std::max)(0, height - top), TRUE);
  UpdateTooltips(bar);
  // Maximize becomes Restore Down; narrow windows hide navigation.
  if (bar.accessibility) bar.accessibility->Update();
  InvalidateBar(bar);
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  const auto found = TitleBars().find(state->browser);
  if (found == TitleBars().end()) return;
  TitleBar& bar = *found->second;
  bar.can_go_back = state->can_go_back;
  bar.can_go_forward = state->can_go_forward;
  bar.loading = state->is_loading;
  bar.title = state->title && *state->title ? utf8_to_wide(state->title)
                                            : bar.fallback_title;
  bar.host = utf8_to_wide(dww::HostOf(state->url));
  // The window title also names the window in the taskbar, so it follows the
  // page even when the title bar hides it.
  SetWindowTextW(bar.window, bar.title.c_str());
  if (bar.accessibility) bar.accessibility->Update();
  InvalidateBar(bar);
}

void Closing(void*, int64_t browser) {
  const auto found = TitleBars().find(browser);
  if (found == TitleBars().end()) return;
  RemoveWindowSubclass(found->second->window, TitleBarProc, kSubclassId);
  if (found->second->tooltip) DestroyWindow(found->second->tooltip);
  TitleBars().erase(found);
}

}  // namespace

namespace dww {

const DWWComposer& DefaultComposer() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged, Layout,
                                    Closing};
  return composer;
}

}  // namespace dww

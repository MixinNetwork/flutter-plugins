// UI Automation for the buttons the default composer draws in the title bar.
// The window keeps its default UIA element; the buttons are added as its
// children next to the WebView.

#ifndef DESKTOP_WEBVIEW_WINDOW_TITLE_BAR_ACCESSIBILITY_H_
#define DESKTOP_WEBVIEW_WINDOW_TITLE_BAR_ACCESSIBILITY_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace dww {

struct AccessibleButton {
  const wchar_t* automation_id;
  std::wstring name;
  bool enabled;
  // Client coordinates; empty while the button is hidden.
  RECT rect;
};

class TitleBarAccessibility {
 public:
  struct State;

  // |buttons| reports the current buttons. |invoke| runs one by index; it is
  // called from a UIA client request and should not block.
  TitleBarAccessibility(HWND window,
                        std::function<std::vector<AccessibleButton>()> buttons,
                        std::function<void(int)> invoke);
  // Disconnects the providers; clients holding them get
  // UIA_E_ELEMENTNOTAVAILABLE.
  ~TitleBarAccessibility();

  // Handles WM_GETOBJECT for the UIA root. Returns false for other requests.
  bool HandleGetObject(WPARAM wparam, LPARAM lparam, LRESULT* result);

  // Raises events for what changed since the last call: name and enabled
  // state, or a structure change when buttons show or hide.
  void Update();

 private:
  std::shared_ptr<State> state_;
  std::vector<AccessibleButton> reported_;
};

}  // namespace dww

#endif  // DESKTOP_WEBVIEW_WINDOW_TITLE_BAR_ACCESSIBILITY_H_

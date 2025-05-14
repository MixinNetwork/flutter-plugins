//
// Created by yangbin on 2022/1/11.
//

#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <string>
#include <map>
#include <shared_mutex>

#include "base_flutter_window.h"
#include "flutter_window.h"
#include "utils.h"


class MultiWindowManager : public std::enable_shared_from_this<MultiWindowManager>, public BaseFlutterWindowCallback {

public:
  static MultiWindowManager* Instance();

  MultiWindowManager();
  ~MultiWindowManager();

  int64_t Create(
    std::string args,
    WindowOptions options
  );

  void AttachFlutterMainWindow(
    HWND main_window_handle,
    std::unique_ptr<InterWindowEventChannel> inter_window_event_channel,
    std::unique_ptr<WindowEventsChannel> window_events_channel,
    flutter::PluginRegistrarWindows* registrar
  );

  void SetHasListeners(int64_t id, bool has_listeners);

  void Show(int64_t id);

  void Hide(int64_t id);

  void Close(int64_t id);

  void Center(int64_t id);

  flutter::EncodableMap GetFrame(int64_t id, double_t devicePixelRatio);

  void SetFrame(int64_t id, double_t x, double_t y, double_t width, double_t height, UINT flags);

  bool IsFocused(int64_t id);

  bool IsFullScreen(int64_t id);

  bool IsMaximized(int64_t id);

  bool IsMinimized(int64_t id);

  bool IsVisible(int64_t id);

  void Maximize(int64_t id, bool vertically);

  void Unmaximize(int64_t id);

  void Minimize(int64_t id);

  void Restore(int64_t id);

  void SetFullScreen(int64_t id, bool is_full_screen);

  void SetStyle(int64_t id, int32_t style, int32_t extended_style);

  void SetBackgroundColor(int64_t id, Color backgroundColor);

  void SetTitle(int64_t id, const std::string& title);

  void SetIgnoreMouseEvents(int64_t id, bool ignore);

  flutter::EncodableList GetAllSubWindowIds();

  void OnWindowClose(int64_t id) override;

  void OnWindowDestroy(int64_t id) override;

private:
  std::map<int64_t, std::unique_ptr<BaseFlutterWindow>> windows_;

  HHOOK mouse_hook_ = nullptr;

  void HandleWindowChannelCall(
    int64_t from_window_id,
    int64_t target_window_id,
    const std::string& call,
    flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static LRESULT CALLBACK MouseProc(int nCode, WPARAM wParam, LPARAM lParam);
};

#endif // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

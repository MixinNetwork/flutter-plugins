//
// Created by yangbin on 2021/10/20.
//

#ifndef _WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_
#define _WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_

#include "string"

#include <flutter/method_channel.h>

#include "memory"

#include <wrl.h>
#include "wil/com.h"
#include "WebView2.h"

class WebviewWindow {

 public:

  using MethodChannelPtr = std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>;

  WebviewWindow(MethodChannelPtr method_channel, int64_t window_id, std::function<void()> on_close_callback);

  virtual ~WebviewWindow();

  using CreateCallback = std::function<void(bool success)>;

  void CreateAndShow(const std::wstring &title, int height, int width, CreateCallback callback);

  void Navigate(const std::wstring& url);

  void AddScriptToExecuteOnDocumentCreated(const std::wstring& javaScript);

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responsponds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND  window,
                                  UINT  message,
                                  WPARAM  wparam,
                                  LPARAM  lparam) noexcept;

  void Close();

  void SetBrightness(int brightness);

 private:

  // Retrieves a class instance pointer for |window|
  static WebviewWindow *GetThisFromHandle(HWND window) noexcept;

  MethodChannelPtr method_channel_;

  HWND hwnd_;

  int64_t window_id_;

  std::function<void()> on_close_callback_;

  // Pointer to WebViewController
  wil::com_ptr<ICoreWebView2Controller> webview_controller_;

  // Pointer to WebView
  wil::com_ptr<ICoreWebView2> webview_;

  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  LRESULT MessageHandler(HWND window,
                         UINT message,
                         WPARAM wparam,
                         LPARAM lparam) noexcept;

  void OnWebviewControllerCreated();

};

#endif //_WEBVIEW_WINDOW_WEBVIEW_WINDOW_H_

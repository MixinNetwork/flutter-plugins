//
// Created by yangbin on 2021/11/15.
//

#ifndef DESKTOP_WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_PLUGIN_H_
#define DESKTOP_WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "strconv.h"
#include "webview_window.h"

#include <memory>

class WebviewWindowPlugin: public flutter::Plugin {
 public:

  using MethodChannelPtr = std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>;

  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit WebviewWindowPlugin(MethodChannelPtr method_channel);

  ~WebviewWindowPlugin() override;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  MethodChannelPtr method_channel_;

  // Declared before windows_ so every borrowed view dies before this engine.
  webview_window::SharedToolbarEngine toolbar_engine_;

  std::map<int64_t, std::shared_ptr<WebviewWindow>> windows_;

  // Guards native close callbacks during plugin teardown.
  std::shared_ptr<bool> lifetime_ = std::make_shared<bool>(true);

};

#endif //DESKTOP_WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_PLUGIN_H_

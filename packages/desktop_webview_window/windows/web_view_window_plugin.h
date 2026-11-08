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

#include <map>
#include <memory>

class WebviewWindowPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

  explicit WebviewWindowPlugin(flutter::BinaryMessenger* messenger);

  ~WebviewWindowPlugin() override;

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;

  void HandleMethodCall(const flutter::MethodCall<Value>& method_call,
                        std::unique_ptr<Result> result);

  void Create(const flutter::EncodableMap& arguments,
              std::unique_ptr<Result> result);

  void Emit(const std::string& method, flutter::EncodableMap args);

  // Declared first: destroyed last, after every window has stopped emitting.
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;

  std::map<int64_t, std::shared_ptr<WebviewWindow>> windows_;

  // Guards native close callbacks during plugin teardown.
  std::shared_ptr<bool> lifetime_ = std::make_shared<bool>(true);
};

#endif  // DESKTOP_WEBVIEW_WINDOW_WINDOWS_WEB_VIEW_PLUGIN_H_

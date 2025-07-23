//
// Created by Konstantin Wachendorff on 2025/03/05.
//

#ifndef DESKTOP_MULTI_WINDOW_WINDOW_EVENTS_CHANNEL_H
#define DESKTOP_MULTI_WINDOW_WINDOW_EVENTS_CHANNEL_H

#include <cstdint>
#include <memory>

#include "flutter/event_channel.h"
#include "flutter/plugin_registrar.h"
#include "flutter/plugin_registrar_windows.h"
#include "flutter/method_channel.h"
#include "flutter/encodable_value.h"

class WindowEventsChannel : public flutter::Plugin {

public:
    using Argument = flutter::EncodableValue;

    static std::unique_ptr<WindowEventsChannel> RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

    WindowEventsChannel(std::unique_ptr<flutter::MethodChannel<Argument>> channel);

    ~WindowEventsChannel() override;

    using MethodCallHandler = std::function<void(const std::string& call, Argument* arguments, std::unique_ptr<flutter::MethodResult<Argument>> result)>;

    void SetMethodCallHandler(MethodCallHandler handler) {
        handler_ = std::move(handler);
    }

    MethodCallHandler handler_;

    std::unique_ptr<flutter::MethodChannel<Argument>> channel_;
};

#endif // DESKTOP_MULTI_WINDOW_WINDOW_EVENTS_CHANNEL_H

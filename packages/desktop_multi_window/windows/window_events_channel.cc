//
// Created by Konstantin Wachendorff on 2025/03/05.
//

#include "window_events_channel.h"
#include "flutter/standard_method_codec.h"

#include <variant>

std::unique_ptr<WindowEventsChannel> WindowEventsChannel::RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
    auto window_registrar = flutter::PluginRegistrarManager::GetInstance()
        ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        window_registrar->messenger(), "mixin.one/flutter_multi_window_events_channel",
        &flutter::StandardMethodCodec::GetInstance());
    return std::make_unique<WindowEventsChannel>(std::move(channel));
}

WindowEventsChannel::WindowEventsChannel(std::unique_ptr<flutter::MethodChannel<Argument>> channel) : channel_(std::move(channel)) {
    channel_->SetMethodCallHandler([this](const flutter::MethodCall<Argument>& call, auto result) {
        if (!handler_) {
            std::cout << "WindowEventsChannel::SetMethodCallHandler: handler_ is null" << std::endl;
            return;
        }
        auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        auto arguments = args->at(flutter::EncodableValue("arguments"));
        handler_(call.method_name(), &arguments, std::move(result));
    });
}

WindowEventsChannel::~WindowEventsChannel() {
    channel_->SetMethodCallHandler(nullptr);
}


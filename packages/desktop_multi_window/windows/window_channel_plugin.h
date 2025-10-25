#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_WINDOW_CHANNEL_PLUGIN_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_WINDOW_CHANNEL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

void WindowChannelPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar);

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_WINDOW_CHANNEL_PLUGIN_H_

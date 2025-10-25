#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_PLUGIN_INTERNAL_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_PLUGIN_INTERNAL_H_

#include "flutter_plugin_registrar.h"

class FlutterWindowWrapper;

void InternalMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar,
    FlutterWindowWrapper* window);

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_PLUGIN_INTERNAL_H_

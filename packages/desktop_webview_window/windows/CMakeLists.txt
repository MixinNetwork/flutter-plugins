cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "desktop_webview_window")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "desktop_webview_window_plugin")

# Composer runtime shared with macOS and Linux.
set(WEBVIEW_SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../src")

add_library(${PLUGIN_NAME} SHARED
        "desktop_webview_window_plugin.cpp"
        "${WEBVIEW_SHARED}/composer_runtime.cc"
        "${WEBVIEW_SHARED}/dart_bridge_api.c"
        "default_composer.cc"
        "navigation_decider.h"
        "navigation_decider.cc"
        "webview_window.h"
        "webview_window.cc"
        "strconv.h"
        "utils.h"
        "utils.cc"
        "web_view.h"
        "web_view.cc"
        "web_view_window_plugin.h"
        "web_view_window_plugin.cc"
        )

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_include_directories(${PLUGIN_NAME} PRIVATE "${WEBVIEW_SHARED}")
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
# Runners include <desktop_webview_window/webview_window_composer.h>.
target_include_directories(${PLUGIN_NAME} PUBLIC
        "${WEBVIEW_SHARED}/include")
target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin flutter_wrapper_app)

# SDK headers, loader DLL and import library: Microsoft.Web.WebView2 1.0.4258.31,
# build/native/include and build/native/x64 in the official NuGet package.
add_library(Webview2 SHARED IMPORTED GLOBAL)
SET_PROPERTY(TARGET Webview2 PROPERTY IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/Webview2Loader.dll)
SET_PROPERTY(TARGET Webview2 PROPERTY IMPORTED_IMPLIB ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/Webview2Loader.dll.lib)

target_link_libraries(${PLUGIN_NAME} PRIVATE Webview2 uxtheme dwmapi advapi32)

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_webview_window_bundled_libraries
        "$<TARGET_FILE:Webview2>"
        PARENT_SCOPE
        )

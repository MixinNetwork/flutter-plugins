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
        "title_bar_accessibility.h"
        "title_bar_accessibility.cc"
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

include("${CMAKE_CURRENT_SOURCE_DIR}/webview2_sdk.cmake")
dww_webview2_arch(WEBVIEW2_ARCH)
set(WEBVIEW2_VERSION "1.0.4258.31")
dww_fetch_webview2_sdk(WEBVIEW2_SDK_DIR "${WEBVIEW2_VERSION}"
        "56f7f4b8bf9aee4b8efefbbdd4f67d5f74ebd1b100ed0806da71bf76af481aa9"
        "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/${WEBVIEW2_VERSION}/microsoft.web.webview2.${WEBVIEW2_VERSION}.nupkg")
add_library(dww_webview2 STATIC IMPORTED)
set_target_properties(dww_webview2 PROPERTIES
        IMPORTED_LOCATION "${WEBVIEW2_SDK_DIR}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib"
        INTERFACE_INCLUDE_DIRECTORIES "${WEBVIEW2_SDK_DIR}/build/native/include"
        INTERFACE_LINK_LIBRARIES version)

target_link_libraries(${PLUGIN_NAME} PRIVATE dww_webview2 uxtheme dwmapi advapi32 comctl32 uiautomationcore)

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_webview_window_bundled_libraries
        ""
        PARENT_SCOPE
        )

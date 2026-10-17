cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "desktop_webview_window")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "desktop_webview_window_plugin")

# Composer runtime shared with macOS and Windows.
set(WEBVIEW_SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../src")

find_package(PkgConfig REQUIRED)
pkg_check_modules(WebKit IMPORTED_TARGET webkit2gtk-4.1)
if (WebKit_FOUND)
  pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-3.0)
else ()
  pkg_check_modules(WebKit REQUIRED IMPORTED_TARGET webkit2gtk-4.0)
  pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-2.4)
endif ()

add_library(${PLUGIN_NAME} SHARED
        "desktop_webview_window_plugin.cc"
        "${WEBVIEW_SHARED}/composer_runtime.cc"
        default_composer.cc
        webview_window.cc
        webview_window.h
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
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::WebKit PkgConfig::LibSoup)

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_webview_window_bundled_libraries
        ""
        PARENT_SCOPE
        )

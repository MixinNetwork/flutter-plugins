cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "desktop_webview_window")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "desktop_webview_window_plugin")

add_library(${PLUGIN_NAME} SHARED
        "desktop_webview_window_plugin.cpp"
        "webview_window.h"
        "webview_window.cc"
        "strconv.h"
        )

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

add_library(Webview2 SHARED IMPORTED GLOBAL)
SET_PROPERTY(TARGET Webview2 PROPERTY IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/Webview2Loader.dll)
SET_PROPERTY(TARGET Webview2 PROPERTY IMPORTED_IMPLIB ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/Webview2Loader.dll.lib)

target_link_libraries(${PLUGIN_NAME} PRIVATE Webview2)

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_webview_window_bundled_libraries
        "$<TARGET_FILE:Webview2>"
        PARENT_SCOPE
        )
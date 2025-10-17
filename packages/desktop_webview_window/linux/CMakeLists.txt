# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "desktop_webview_window")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "desktop_webview_window_plugin")


# === WebKit and libsoup dependencies ===
find_package(PkgConfig REQUIRED)

# Try webkit2gtk-4.1 first, then fallback to 4.0
pkg_check_modules(WebKit IMPORTED_TARGET webkit2gtk-4.1)
if (NOT WebKit_FOUND)
    pkg_check_modules(WebKit REQUIRED IMPORTED_TARGET webkit2gtk-4.0)
endif ()

# Try libsoup-3.0, fallback to libsoup-2.4
pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-3.0)
if (NOT LibSoup_FOUND)
    pkg_check_modules(LibSoup REQUIRED IMPORTED_TARGET libsoup-2.4)
endif ()

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
        "desktop_webview_window_plugin.cc"
        "webview_window.cc"
        "webview_window.h"
        "message_channel_plugin.h"
        "message_channel_plugin.cc"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
        ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-spec ific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::WebKit)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::LibSoup)


# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(desktop_webview_window_bundled_libraries
        ""
        PARENT_SCOPE
)

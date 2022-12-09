cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "win_toast")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "win_toast_plugin")

add_library(${PLUGIN_NAME} SHARED
  win_toast_plugin.cpp
  pch.h
  DesktopNotificationManagerCompat.h
  DesktopNotificationManagerCompat.cpp
  notification_manager.h
  notification_manager.cc
  dll_importer.cc
  dll_importer.h
  )


if (WIN_TOAST_ENABLE_WIN_RT)
  message(warning "WIN_TOAST_ENABLE_WIN_RT is unnecessary. removed since 0.3.0")
endif ()
if (DEFINED WIN_TOAST_WRL_ACTIVATOR_CLSID)
  message(warning "WIN_TOAST_WRL_ACTIVATOR_CLSID is unnecessary. removed since 0.3.0")
endif ()
if (WIN_TOAST_ENABLE_WRL)
  message(warning "WIN_TOAST_ENABLE_WRL is unnecessary. removed since 0.3.0")
endif ()

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(win_toast_bundled_libraries
  ""
  PARENT_SCOPE
  )

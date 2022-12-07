cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "win_toast")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "win_toast_plugin")

option(WIN_TOAST_ENABLE_WIN_RT "enable win_rt toast" OFF)
option(WIN_TOAST_ENABLE_WRL "enable wrl toast" OFF)

add_library(${PLUGIN_NAME} SHARED
  win_toast_plugin.cpp
  pch.h
  DesktopNotificationManagerCompat.h
  DesktopNotificationManagerCompat.cpp
  notification_manager_wrl.cc
  notification_manager_wrl.h
  notification_manager.h
  notification_manager.cc
  notification_manager_win_rt.cc
  notification_manager_win_rt.h
  DesktopNotificationManagerCompat2.h
  DesktopNotificationManagerCompat2.cpp
  )


if(WIN_TOAST_ENABLE_WIN_RT)
  TARGET_COMPILE_DEFINITIONS(${PLUGIN_NAME} PRIVATE  WIN_TOAST_ENABLE_WIN_RT=1)
  message("enable win_rt toast")
endif()

if(WIN_TOAST_ENABLE_WRL)
  TARGET_COMPILE_DEFINITIONS(${PLUGIN_NAME} PRIVATE  WIN_TOAST_ENABLE_WRL=1)
  message("enable wrl toast")
endif()

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

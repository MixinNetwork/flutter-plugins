cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "desktop_drop")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "desktop_drop_plugin")

set(DROP_BRIDGE "${CMAKE_CURRENT_SOURCE_DIR}/../macos/desktop_drop/Sources/desktop_drop_ffi")

add_library(${PLUGIN_NAME} SHARED
  "desktop_drop_plugin.cpp"
  "${DROP_BRIDGE}/desktop_drop_ffi.cc"
  "${DROP_BRIDGE}/dart_bridge_api.c"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(desktop_drop_bundled_libraries
  ""
  PARENT_SCOPE
)

target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_include_directories(${PLUGIN_NAME} PRIVATE "${DROP_BRIDGE}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE ole32 shell32)

cmake_minimum_required(VERSION 3.10)
project(desktop_drop_ffi LANGUAGES C CXX)
set(DROP_BRIDGE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
add_library(desktop_drop_ffi SHARED
  src/main/cpp/ffi_transport.cc
  "${DROP_BRIDGE}/desktop_drop_ffi.cc"
  "${DROP_BRIDGE}/dart_bridge_api.c")
target_include_directories(desktop_drop_ffi PRIVATE "${DROP_BRIDGE}")
target_compile_features(desktop_drop_ffi PRIVATE cxx_std_17)
target_link_libraries(desktop_drop_ffi dl)

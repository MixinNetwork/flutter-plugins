# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(ogg_opus_player_library VERSION 0.0.1 LANGUAGES C CXX)

include_directories(SDL2)
include_directories(dart)

add_library(ogg_opus_player SHARED
  "ogg_opus_player.cc"
  "dart/dart_api_dl.c"
  "ogg_opus_recorder.cc"
  "sonic.c"
  )

set_target_properties(ogg_opus_player PROPERTIES
  PUBLIC_HEADER ogg_opus_player.h
  OUTPUT_NAME "ogg_opus_player"
  )

if (UNIX AND NOT APPLE)
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_arm64/libopusenc.a)
    target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_arm64/libopusfile.a)
  else()
    target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libopusenc.a)
    target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libopusfile.a)
  endif()
  target_link_libraries(ogg_opus_player -lSDL2 -lopus -logg)
elseif (WIN32)
  add_library(ogg STATIC IMPORTED)
  set_target_properties(ogg PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/libogg.lib
    )
  add_library(opus STATIC IMPORTED)
  set_target_properties(opus PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/opus.lib
    )
  add_library(opusfile STATIC IMPORTED)
  set_target_properties(opusfile PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/opusfile.lib
    )
  add_library(opusenc STATIC IMPORTED)
  set_target_properties(opusenc PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/opusenc.lib
    )
  add_library(sdl2 SHARED IMPORTED GLOBAL)
  set_target_properties(sdl2 PROPERTIES
    IMPORTED_IMPLIB ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/SDL2.lib
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/windows_x64/SDL2.dll
    )
  target_link_libraries(ogg_opus_player
    ogg opus opusfile opusenc sdl2
    )
  set_property(TARGET ogg_opus_player APPEND PROPERTY LINK_FLAGS "/NODEFAULTLIB:LIBCMT")
endif ()

target_compile_definitions(ogg_opus_player PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size.
  target_link_options(ogg_opus_player PRIVATE "-Wl,-z,max-page-size=16384")
endif()

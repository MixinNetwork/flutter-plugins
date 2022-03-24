# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(ogg_opus_player_library VERSION 0.0.1 LANGUAGES C CXX)

include_directories(SDL2)

add_library(ogg_opus_player SHARED
  "ogg_opus_player.cc"
  )

set_target_properties(ogg_opus_player PROPERTIES
  PUBLIC_HEADER ogg_opus_player.h
  OUTPUT_NAME "ogg_opus_player"
  )

if (UNIX AND NOT APPLE)
  add_library(ogg SHARED IMPORTED GLOBAL)
  set_target_properties(ogg PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libogg.so)
  add_library (opus SHARED IMPORTED GLOBAL)
  set_target_properties(opus PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libopus.so)
  target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libopusenc.a)
  target_link_libraries(ogg_opus_player ${CMAKE_CURRENT_SOURCE_DIR}/libs/linux_amd64/libopusfile.a)
  target_link_libraries(ogg_opus_player -lSDL2 ogg opus)
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
endif ()

target_compile_definitions(ogg_opus_player PUBLIC DART_SHARED_LIB)

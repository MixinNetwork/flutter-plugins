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

if(UNIX AND NOT APPLE)
 # target_link_libraries(main ${CMAKE_SOURCE_DIR}/libbingitup.a)
  target_link_libraries(ogg_opus_player
    -lopus -lopusfile -logg -lm -lSDL2
  )
endif()

target_compile_definitions(ogg_opus_player PUBLIC DART_SHARED_LIB)

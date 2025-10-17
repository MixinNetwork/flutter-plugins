cmake_minimum_required(VERSION 3.4.1)
set(CMAKE_CXX_STANDARD 14)

set(distribution_OPUS_DIR ${CMAKE_SOURCE_DIR}/opus)

add_library(lib_opus STATIC IMPORTED)
set_target_properties(lib_opus PROPERTIES IMPORTED_LOCATION
        ${distribution_OPUS_DIR}/lib/${ANDROID_ABI}/libopus.a)

add_library(lib_ogg STATIC IMPORTED)
set_target_properties(lib_ogg PROPERTIES IMPORTED_LOCATION
        ${distribution_OPUS_DIR}/lib/${ANDROID_ABI}/libogg.a)

add_library(lib_opusenc STATIC IMPORTED)
set_target_properties(lib_opusenc PROPERTIES IMPORTED_LOCATION
        ${distribution_OPUS_DIR}/lib/${ANDROID_ABI}/libopusenc.a)

add_library(ogg_opus_player_plugin SHARED
        audio.c)

target_include_directories(ogg_opus_player_plugin PRIVATE
        ${distribution_OPUS_DIR}/include)

target_link_libraries(ogg_opus_player_plugin
        android
        lib_opusenc
        lib_opus
        lib_ogg
        log)

# Support Android 15 16k page size
target_link_options(ogg_opus_player_plugin PRIVATE "-Wl,-z,max-page-size=16384")

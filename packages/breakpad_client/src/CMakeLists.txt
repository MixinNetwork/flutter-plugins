# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(breakpad_client_library VERSION 0.0.1 LANGUAGES CXX)

add_compile_options("-fPIC")
# libbreakpad_client target

if (WIN32)
    file(GLOB_RECURSE LIBBREAKPAD_CLIENT_SOURCES breakpad/src/client/windows/*.cc breakpad/src/common/windows/*.cc)
    include_directories("$ENV{VSINSTALLDIR}/DIA SDK/include")
elseif (APPLE)
    add_definitions(-DHAVE_MACH_O_NLIST_H)
    file(GLOB_RECURSE LIBBREAKPAD_CLIENT_SOURCES breakpad/src/client/mac/*.cc breakpad/src/common/mac/*.cc)
    list(APPEND LIBBREAKPAD_CLIENT_SOURCES breakpad/src/common/mac/MachIPC.mm)
else ()
    add_definitions(-DHAVE_A_OUT_H)
    file(GLOB_RECURSE LIBBREAKPAD_CLIENT_SOURCES breakpad/src/client/linux/*.cc breakpad/src/common/linux/*.cc)
endif ()
file(GLOB LIBBREAKPAD_COMMON_SOURCES breakpad/src/common/*.cc breakpad/src/common/*.c breakpad/src/client/*.cc)
list(APPEND LIBBREAKPAD_CLIENT_SOURCES ${LIBBREAKPAD_COMMON_SOURCES})

list(FILTER LIBBREAKPAD_CLIENT_SOURCES EXCLUDE REGEX "/sender|/tests|/unittests|/testcases|_unittest|_test")

if (WIN32)
    list(FILTER LIBBREAKPAD_CLIENT_SOURCES EXCLUDE REGEX "language.cc|path_helper.cc|stabs_to_module.cc|stabs_reader.cc|minidump_file_writer.cc")
elseif (NOT APPLE)
    try_compile(HAVE_GETCONTEXT ${CMAKE_BINARY_DIR}/check_getcontext ${CMAKE_CURRENT_LIST_DIR}/check_getcontext.cc OUTPUT_VARIABLE BUILD_OUT)
    if (NOT HAVE_GETCONTEXT)
        enable_language(ASM)
        list(APPEND LIBBREAKPAD_CLIENT_SOURCES breakpad/src/common/linux/breakpad_getcontext.S)
    endif ()
endif ()


add_library(g_breakpad_client STATIC ${LIBBREAKPAD_CLIENT_SOURCES})


if (WIN32)
    target_link_libraries(g_breakpad_client PRIVATE wininet.lib)
elseif (APPLE)
    find_library(CoreFoundation_FRAMEWORK CoreFoundation)
    target_link_libraries(g_breakpad_client PRIVATE ${CoreFoundation_FRAMEWORK})
else ()
    find_library(PTHREAD_LIBRARIES pthread)
    if (PTHREAD_LIBRARIES)
        target_link_libraries(g_breakpad_client PRIVATE ${PTHREAD_LIBRARIES})
    endif ()
    if (HAVE_GETCONTEXT)
        target_compile_definitions(g_breakpad_client PRIVATE HAVE_GETCONTEXT=1)
    endif ()
endif ()

target_include_directories(g_breakpad_client
        PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/breakpad/src>
        $<INSTALL_INTERFACE:include>
)

if (WIN32)
    set(HEADER_EXCLUDE_REGEX "/apple|/ios|/linux|/mac|/solaris|/android|/dwarf|/tests|/testdata|/unittests")
elseif (APPLE)
    set(HEADER_EXCLUDE_REGEX "/apple|/ios|/linux|/windows|/solaris|/android|/dwarf|/tests|/testdata|/unittests|/sender|/testapp|\.xcodeproj|/gcov")
else ()
    set(HEADER_EXCLUDE_REGEX "/apple|/ios|/windows|/mac|/solaris|/android|/dwarf|/tests|/testdata|/unittests")
endif ()

install(
        DIRECTORY breakpad/src/client breakpad/src/common breakpad/src/google_breakpad
        DESTINATION include/
        FILES_MATCHING
        PATTERN "*.h"
        REGEX ${HEADER_EXCLUDE_REGEX} EXCLUDE
)

add_library(breakpad_client SHARED
        "breakpad_client.cpp"
)

set_target_properties(breakpad_client PROPERTIES
        PUBLIC_HEADER breakpad_client.h
        OUTPUT_NAME "breakpad_client"
)


target_link_libraries(breakpad_client g_breakpad_client)

target_compile_definitions(breakpad_client PUBLIC DART_SHARED_LIB)

# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(mixin_logger_library VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

add_library(mixin_logger SHARED
        "mixin_logger.cpp"
)

set_target_properties(mixin_logger PROPERTIES
        PUBLIC_HEADER include/mixin_logger/mixin_logger.h
        OUTPUT_NAME "mixin_logger"
)

target_compile_definitions(mixin_logger PUBLIC DART_SHARED_LIB)
target_include_directories(mixin_logger PUBLIC include)

find_package(GTest)
if (GTest_FOUND)
    enable_testing()
    add_executable(UnitTests test.cpp)
    target_link_libraries(UnitTests GTest::GTest GTest::Main)
    add_test(NAME UnitTests COMMAND UnitTests)
endif ()


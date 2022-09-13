cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "pasteboard")
project(${PROJECT_NAME} LANGUAGES CXX)


# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "pasteboard_plugin")

add_library(${PLUGIN_NAME} SHARED
        "pasteboard_plugin.cpp"
        )
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# GdiPlus doesn't compile with /W4 warning level
target_compile_options(${PLUGIN_NAME} PRIVATE
  $<$<CXX_COMPILER_ID:MSVC>:/W3 /WX>
  $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic -Werror>
)


# List of absolute paths to libraries that should be bundled with the plugin
set(pasteboard_bundled_libraries
        ""
        PARENT_SCOPE
        )

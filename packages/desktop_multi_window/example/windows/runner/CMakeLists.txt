cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} flutter_assemble)

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND mt.exe -nologo
          -manifest \"${CMAKE_CURRENT_SOURCE_DIR}/runner.uiaccess.manifest\"
          -outputresource:\"$<TARGET_FILE:${BINARY_NAME}>\";#1
  COMMENT "Embedding uiAccess=true manifest after build"
)

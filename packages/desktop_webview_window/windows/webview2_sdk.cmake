# FetchContent keeps the SDK under the application's build directory. Repeated
# builds reuse it; flutter clean removes it along with other build artifacts.
function(dww_fetch_webview2_sdk output version sha256 url)
  include(FetchContent)
  if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
  endif()
  FetchContent_Declare(dww_webview2_sdk
      URL "${url}"
      URL_HASH "SHA256=${sha256}"
      TLS_VERIFY ON
      TIMEOUT 180
      DOWNLOAD_NAME "webview2.zip")
  FetchContent_MakeAvailable(dww_webview2_sdk)
  set(sdk_root "${dww_webview2_sdk_SOURCE_DIR}")
  foreach(path IN ITEMS
      build/native/include/WebView2.h
      build/native/include/WebView2EnvironmentOptions.h
      build/native/x64/WebView2LoaderStatic.lib
      build/native/arm64/WebView2LoaderStatic.lib)
    if(NOT EXISTS "${sdk_root}/${path}")
      message(FATAL_ERROR "WebView2 SDK ${version} is incomplete: ${sdk_root}/${path}")
    endif()
  endforeach()
  message(STATUS "WebView2 SDK ${version}: ${sdk_root}")
  set(${output} "${sdk_root}" PARENT_SCOPE)
endfunction()

function(dww_webview2_arch output)
  # Use the target, never the host CPU or pointer size (x64 and ARM64 are both
  # 64-bit). MSVC's architecture also covers non-Visual-Studio generators.
  if(CMAKE_VS_PLATFORM_NAME)
    set(platform "${CMAKE_VS_PLATFORM_NAME}")
  else()
    set(platform "${MSVC_CXX_ARCHITECTURE_ID}")
  endif()
  string(TOLOWER "${platform}" platform)
  if(NOT platform STREQUAL "x64" AND NOT platform STREQUAL "arm64")
    message(FATAL_ERROR "Unsupported WebView2 target architecture: '${platform}'. Expected x64 or ARM64.")
  endif()
  set(${output} "${platform}" PARENT_SCOPE)
endfunction()

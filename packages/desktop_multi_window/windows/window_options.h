// window_options.h
#pragma once
#include <string>
#include <windows.h>
#include <iostream>
#include <iomanip>
#include <flutter/standard_method_codec.h>
#include <type_traits>

struct WindowOptions
{
  std::wstring title;
  DWORD style;
  DWORD exStyle;
  int x;
  int y;
  int width;
  int height;

  WindowOptions()
    : title(L""), style(WS_OVERLAPPEDWINDOW), exStyle(0),
    x(10), y(10), width(1280), height(720) {
  }

  // Parse the window options from a flutter::EncodableMap.
  void Parse(const flutter::EncodableMap& windows_map) {
    // Helper lambda to extract int values from the map.
    auto getInt = [&](const std::string& key, int defaultValue) -> int {
      auto iter = windows_map.find(flutter::EncodableValue(key));
      if (iter != windows_map.end()) {
        return std::visit([&](auto&& arg) -> int {
          using T = std::decay_t<decltype(arg)>;
          if constexpr (std::is_integral_v<T> || std::is_floating_point_v<T>) {
            return static_cast<int>(arg);
          } else {
            return defaultValue;
          } }, iter->second);
      }
      return defaultValue;
    };

    // Helper lambda to extract string values and convert them to std::wstring.
    auto getString = [&](const std::string& key, const std::wstring& defaultValue) -> std::wstring {
      auto iter = windows_map.find(flutter::EncodableValue(key));
      if (iter != windows_map.end() && std::holds_alternative<std::string>(iter->second)) {
        std::string str = std::get<std::string>(iter->second);
        return std::wstring(str.begin(), str.end());
      }
      return defaultValue;
    };

    style = static_cast<DWORD>(getInt("style", style));
    exStyle = static_cast<DWORD>(getInt("exStyle", exStyle));
    x = getInt("x", x);
    y = getInt("y", y);
    width = getInt("width", width);
    height = getInt("height", height);
    title = getString("title", title);
  }

  // Print function for debugging.
  void Print() const {
    std::wcout << L"WindowOptions:" << std::endl;
    std::wcout << L"  Title: " << title << std::endl;
    std::wcout << L"  Style: 0x" << std::hex << style << std::dec << std::endl;
    std::wcout << L"  ExStyle: 0x" << std::hex << exStyle << std::dec << std::endl;
    std::wcout << L"  Position: (" << x << L", " << y << L")" << std::endl;
    std::wcout << L"  Size: " << width << L" x " << height << std::endl;
  }
};
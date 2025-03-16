// window_options.h
#pragma once
#include <string>
#include <windows.h>
#include <iostream>
#include <iomanip>
#include <flutter/standard_method_codec.h>
#include <type_traits>
#include <algorithm>

// Helper lambda to extract int values from the map.
auto getInt = [&](const flutter::EncodableMap& map, const std::string& key, int defaultValue) -> int {
  auto iter = map.find(flutter::EncodableValue(key));
  if (iter != map.end()) {
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

// Helper lambda to extract double values from the map.
auto getDouble = [&](const flutter::EncodableMap& map, const std::string& key, double defaultValue) -> double {
  auto iter = map.find(flutter::EncodableValue(key));
  if (iter != map.end()) {
    return std::visit([&](auto&& arg) -> double {
      using T = std::decay_t<decltype(arg)>;
      if constexpr (std::is_integral_v<T> || std::is_floating_point_v<T>) {
        return static_cast<double>(arg);
      } else {
        return defaultValue;
      } }, iter->second);
  }
  return defaultValue;
};

// Helper lambda to extract string values and convert them to std::wstring.
auto getString = [&](const flutter::EncodableMap& map, const std::string& key, const std::wstring& defaultValue) -> std::wstring {
  auto iter = map.find(flutter::EncodableValue(key));
  if (iter != map.end() && std::holds_alternative<std::string>(iter->second)) {
    std::string str = std::get<std::string>(iter->second);
    return std::wstring(str.begin(), str.end());
  }
  return defaultValue;
};

struct Color {
  int r, g, b, a;

  // Default constructor (black, fully opaque)
  Color() : r(0), g(0), b(0), a(255) {}

  // Constructor with values
  Color(int red, int green, int blue, int alpha = 255)
    : r(std::clamp(red, 0, 255))
    , g(std::clamp(green, 0, 255))
    , b(std::clamp(blue, 0, 255))
    , a(std::clamp(alpha, 0, 255)) {
  }

  Color(double red, double green, double blue, double alpha = 1.0)
    : r(std::clamp(static_cast<int>(red * 255), 0, 255))
    , g(std::clamp(static_cast<int>(green * 255), 0, 255))
    , b(std::clamp(static_cast<int>(blue * 255), 0, 255))
    , a(std::clamp(static_cast<int>(alpha * 255), 0, 255)) {
  }

  // Create from COLORREF
  static Color FromColorRef(COLORREF ref) {
    return Color(
      GetRValue(ref),
      GetGValue(ref),
      GetBValue(ref),
      255
    );
  }

  // Create from ARGB
  static Color FromARGB(uint32_t argb) {
    return Color(
      (int)((argb >> 16) & 0xFF),
      (int)((argb >> 8) & 0xFF),
      (int)(argb & 0xFF),
      (int)((argb >> 24) & 0xFF)
    );
  }

  COLORREF toColorRef() const {
    return RGB(r, g, b);
  }

  uint32_t toARGB() const {
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  uint32_t toABGR() const {
    return (a << 24) | (b << 16) | (g << 8) | r;
  }

  // Check if color is transparent
  bool isTransparent() const {
    return a == 0;
  }

  // Check if color is fully opaque
  bool isOpaque() const {
    return a == 255;
  }

  static Color ParseColor(const flutter::EncodableMap& color_map) {
    // Get color components with bounds checking
    auto red = getDouble(color_map, "red", 0.5);
    auto green = getDouble(color_map, "green", 0.5);
    auto blue = getDouble(color_map, "blue", 0.5);
    auto alpha = getDouble(color_map, "alpha", 1.0);

    return Color(red, green, blue, alpha);
  }
};

struct WindowOptions
{
  std::wstring title;
  DWORD style;
  DWORD exStyle;
  int left;
  int top;
  int width;
  int height;
  Color backgroundColor;

  WindowOptions()
    : title(L""), style(WS_OVERLAPPEDWINDOW), exStyle(0),
    left(10), top(10), width(1280), height(720) {
  }

  // Parse the window options from a flutter::EncodableMap.
  void Parse(const flutter::EncodableMap& windows_map) {
    style = static_cast<DWORD>(getInt(windows_map, "style", style));
    exStyle = static_cast<DWORD>(getInt(windows_map, "exStyle", exStyle));
    left = getInt(windows_map, "left", left);
    top = getInt(windows_map, "top", top);
    width = getInt(windows_map, "width", width);
    height = getInt(windows_map, "height", height);
    title = getString(windows_map, "title", title);
    try {
      auto backgroundColorIter = windows_map.find(flutter::EncodableValue("backgroundColor"));
      if (backgroundColorIter != windows_map.end() &&
        std::holds_alternative<flutter::EncodableMap>(backgroundColorIter->second)) {
        const auto& backgroundColorMap = std::get<flutter::EncodableMap>(backgroundColorIter->second);
        backgroundColor = Color::ParseColor(backgroundColorMap);
      }
    } catch (const std::exception& e) {
      std::cerr << L"Error parsing background color: " << e.what() << std::endl;
    }
  }

  // Print function for debugging.
  void Print() const {
    std::wcout << L"WindowOptions:" << std::endl;
    std::wcout << L"  Title: " << title << std::endl;
    std::wcout << L"  Style: 0x" << std::hex << style << std::dec << std::endl;
    std::wcout << L"  ExStyle: 0x" << std::hex << exStyle << std::dec << std::endl;
    std::wcout << L"  Position: (" << left << L", " << top << L")" << std::endl;
    std::wcout << L"  Size: " << width << L" x " << height << std::endl;
    std::wcout << L"  Background Color: " << backgroundColor.toARGB() << std::endl;
  }
};


#ifndef DESKTOP_MULTI_WINDOW_UTILS_H
#define DESKTOP_MULTI_WINDOW_UTILS_H

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

inline int64_t GetIntegerValue(const flutter::EncodableValue& value) {
    if (std::holds_alternative<int32_t>(value)) {
        return std::get<int32_t>(value);
    } else if (std::holds_alternative<int64_t>(value)) {
        return std::get<int64_t>(value);
    }
    throw std::runtime_error("Value is not an integer");
}

inline const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map, const char* key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it == map.end()) {
        return nullptr;
    }
    return &(it->second);
}

inline void PrintEncodableValue(const flutter::EncodableValue& value, int indent = 0) {
    std::string indentStr(indent, ' ');
    std::visit([&](auto&& arg)
    {
        using T = std::decay_t<decltype(arg)>;
        if constexpr (std::is_same_v<T, std::nullptr_t>) {
            std::cout << indentStr << "null";
        } else if constexpr (std::is_same_v<T, bool>) {
            std::cout << indentStr << (arg ? "true" : "false");
        } else if constexpr (std::is_same_v<T, int32_t>) {
            std::cout << indentStr << arg;
        } else if constexpr (std::is_same_v<T, int64_t>) {
            std::cout << indentStr << arg;
        } else if constexpr (std::is_same_v<T, double>) {
            std::cout << indentStr << arg;
        } else if constexpr (std::is_same_v<T, std::string>) {
            std::cout << indentStr << "\"" << arg << "\"";
        } else if constexpr (std::is_same_v<T, flutter::EncodableList>) {
            std::cout << indentStr << "[\n";
            for (const auto& elem : arg) {
                PrintEncodableValue(elem, indent + 2);
                std::cout << "\n";
            }
            std::cout << indentStr << "]";
        } else if constexpr (std::is_same_v<T, flutter::EncodableMap>) {
            std::cout << indentStr << "{\n";
            for (const auto& pair : arg) {
                PrintEncodableValue(pair.first, indent + 2);
                std::cout << ": ";
                PrintEncodableValue(pair.second, indent + 2);
                std::cout << "\n";
            }
            std::cout << indentStr << "}";
        } else {
            std::cout << indentStr << "Unknown type";
        } }, value);
}

#endif // DESKTOP_MULTI_WINDOW_UTILS_H

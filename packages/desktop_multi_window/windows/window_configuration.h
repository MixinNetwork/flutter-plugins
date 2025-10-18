#pragma once

#include <string>
#include <flutter/encodable_value.h>
#include <iostream>

struct WindowConfiguration {
  std::string arguments;
  bool hidden_at_launch = false;
  
  static WindowConfiguration FromEncodableMap(
      const flutter::EncodableMap* map) {
    WindowConfiguration config;
    
    if (!map) return config;
    
    try {
      auto it = map->find(flutter::EncodableValue("arguments"));
      if (it != map->end()) {
        config.arguments = std::get<std::string>(it->second);
      }
      
      it = map->find(flutter::EncodableValue("hiddenAtLaunch"));
      if (it != map->end()) {
        config.hidden_at_launch = std::get<bool>(it->second);
      }
    } catch (const std::exception& e) {
      std::cerr << "Failed to parse WindowConfiguration: " << e.what() 
                << std::endl;
    }
    
    return config;
  }
};
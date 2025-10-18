#pragma once

#include <string>
#include <flutter/encodable_value.h>
#include <iostream>

struct Rect {
  double left = 0;
  double top = 0;
  double width = 800;
  double height = 600;
};

struct WindowConfiguration {
  std::string arguments;
  std::string title;
  Rect frame;
  bool resizable = true;
  bool hide_title_bar = false;
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
      
      it = map->find(flutter::EncodableValue("title"));
      if (it != map->end()) {
        config.title = std::get<std::string>(it->second);
      }
      
      it = map->find(flutter::EncodableValue("frame"));
      if (it != map->end()) {
        auto frame_map = std::get_if<flutter::EncodableMap>(&it->second);
        if (frame_map) {
          auto left_it = frame_map->find(flutter::EncodableValue("left"));
          if (left_it != frame_map->end()) {
            config.frame.left = std::get<double>(left_it->second);
          }
          
          auto top_it = frame_map->find(flutter::EncodableValue("top"));
          if (top_it != frame_map->end()) {
            config.frame.top = std::get<double>(top_it->second);
          }
          
          auto width_it = frame_map->find(flutter::EncodableValue("width"));
          if (width_it != frame_map->end()) {
            config.frame.width = std::get<double>(width_it->second);
          }
          
          auto height_it = frame_map->find(flutter::EncodableValue("height"));
          if (height_it != frame_map->end()) {
            config.frame.height = std::get<double>(height_it->second);
          }
        }
      }
      
      it = map->find(flutter::EncodableValue("resizable"));
      if (it != map->end()) {
        config.resizable = std::get<bool>(it->second);
      }
      
      it = map->find(flutter::EncodableValue("hideTitleBar"));
      if (it != map->end()) {
        config.hide_title_bar = std::get<bool>(it->second);
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
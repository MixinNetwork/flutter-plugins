#include "window_channel_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_result_functions.h>

#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace {

enum class ChannelMode { kUnidirectional, kBidirectional };

enum class RegistrationOutcome {
  kAdded,
  kAlreadyRegistered,
  kLimitReached,
  kModeConflict
};

class WindowChannelPlugin;

class ChannelRegistry {
 public:
  static ChannelRegistry& GetInstance() {
    static ChannelRegistry instance;
    return instance;
  }

  RegistrationOutcome Register(const std::string& channel,
                                WindowChannelPlugin* plugin,
                                ChannelMode mode) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (mode == ChannelMode::kUnidirectional) {
      return RegisterUnidirectional(channel, plugin);
    } else {
      return RegisterBidirectional(channel, plugin);
    }
  }

 private:
  RegistrationOutcome RegisterUnidirectional(const std::string& channel,
                                              WindowChannelPlugin* plugin) {
    // Check if already used in bidirectional mode
    if (bidirectional_channels_.find(channel) !=
        bidirectional_channels_.end()) {
      return RegistrationOutcome::kModeConflict;
    }

    auto it = unidirectional_channels_.find(channel);
    if (it != unidirectional_channels_.end()) {
      if (it->second == plugin) {
        return RegistrationOutcome::kAlreadyRegistered;
      }
      // Already registered by another plugin
      return RegistrationOutcome::kLimitReached;
    }

    unidirectional_channels_[channel] = plugin;
    return RegistrationOutcome::kAdded;
  }

  RegistrationOutcome RegisterBidirectional(const std::string& channel,
                                             WindowChannelPlugin* plugin) {
    // Check if already used in unidirectional mode
    if (unidirectional_channels_.find(channel) !=
        unidirectional_channels_.end()) {
      return RegistrationOutcome::kModeConflict;
    }

    auto& plugins = bidirectional_channels_[channel];

    // Check if already registered
    if (plugins.find(plugin) != plugins.end()) {
      return RegistrationOutcome::kAlreadyRegistered;
    }

    // Check limit
    if (plugins.size() >= 2) {
      return RegistrationOutcome::kLimitReached;
    }

    plugins.insert(plugin);
    return RegistrationOutcome::kAdded;
  }

 public:
  void Unregister(const std::string& channel, WindowChannelPlugin* plugin) {
    std::lock_guard<std::mutex> lock(mutex_);

    // Try unidirectional
    auto uni_it = unidirectional_channels_.find(channel);
    if (uni_it != unidirectional_channels_.end() &&
        uni_it->second == plugin) {
      unidirectional_channels_.erase(uni_it);
      return;
    }

    // Try bidirectional
    auto bi_it = bidirectional_channels_.find(channel);
    if (bi_it != bidirectional_channels_.end()) {
      bi_it->second.erase(plugin);
      if (bi_it->second.empty()) {
        bidirectional_channels_.erase(bi_it);
      }
    }
  }

  WindowChannelPlugin* GetTarget(const std::string& channel,
                                  WindowChannelPlugin* from) {
    std::lock_guard<std::mutex> lock(mutex_);

    // Check unidirectional - anyone can call
    auto uni_it = unidirectional_channels_.find(channel);
    if (uni_it != unidirectional_channels_.end()) {
      return uni_it->second;
    }

    // Check bidirectional - only peer can call
    auto bi_it = bidirectional_channels_.find(channel);
    if (bi_it != bidirectional_channels_.end()) {
      const auto& plugins = bi_it->second;

      // Check if caller is in the pair
      if (plugins.find(from) == plugins.end()) {
        return nullptr;
      }

      // Return the peer
      for (auto* plugin : plugins) {
        if (plugin != from) {
          return plugin;
        }
      }
    }

    return nullptr;
  }

  bool HasRegistrations(const std::string& channel) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (unidirectional_channels_.find(channel) !=
        unidirectional_channels_.end()) {
      return true;
    }

    auto it = bidirectional_channels_.find(channel);
    return it != bidirectional_channels_.end() && !it->second.empty();
  }

 private:
  ChannelRegistry() = default;
  std::mutex mutex_;
  std::map<std::string, WindowChannelPlugin*> unidirectional_channels_;
  std::map<std::string, std::set<WindowChannelPlugin*>>
      bidirectional_channels_;
};

class WindowChannelPlugin : public flutter::Plugin {
 public:
  WindowChannelPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<>>(
        registrar->messenger(), "mixin.one/desktop_multi_window/channels",
        &flutter::StandardMethodCodec::GetInstance());

    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<>& call,
               std::unique_ptr<flutter::MethodResult<>> result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~WindowChannelPlugin() {
    for (const auto& channel : registered_channels_) {
      ChannelRegistry::GetInstance().Unregister(channel, this);
    }
  }

  void InvokeMethod(const std::string& channel,
                    const flutter::EncodableValue& arguments,
                    std::unique_ptr<flutter::MethodResult<>> result) {
    // Check if this plugin has registered this channel
    if (std::find(registered_channels_.begin(), registered_channels_.end(),
                  channel) == registered_channels_.end()) {
      result->Error("CHANNEL_NOT_FOUND",
                    "channel " + channel + " not found in this engine");
      return;
    }

    channel_->InvokeMethod("methodCall", std::make_unique<flutter::EncodableValue>(arguments),
                          std::move(result));
  }

 private:
  void HandleMethodCall(const flutter::MethodCall<>& call,
                        std::unique_ptr<flutter::MethodResult<>> result) {
    const auto& method = call.method_name();

    if (method == "registerMethodHandler") {
      auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("INVALID_ARGUMENTS", "arguments must be a map");
        return;
      }

      auto channel_it = args->find(flutter::EncodableValue("channel"));
      if (channel_it == args->end()) {
        result->Error("INVALID_ARGUMENTS", "channel is required");
        return;
      }

      auto* channel = std::get_if<std::string>(&channel_it->second);
      if (!channel) {
        result->Error("INVALID_ARGUMENTS", "channel must be a string");
        return;
      }

      // Get mode (default to bidirectional)
      ChannelMode mode = ChannelMode::kBidirectional;
      auto mode_it = args->find(flutter::EncodableValue("mode"));
      if (mode_it != args->end()) {
        auto* mode_str = std::get_if<std::string>(&mode_it->second);
        if (mode_str) {
          if (*mode_str == "unidirectional") {
            mode = ChannelMode::kUnidirectional;
          } else if (*mode_str == "bidirectional") {
            mode = ChannelMode::kBidirectional;
          } else {
            result->Error("INVALID_MODE",
                          "invalid mode: " + *mode_str +
                              ", must be 'unidirectional' or 'bidirectional'");
            return;
          }
        }
      }

      auto outcome = ChannelRegistry::GetInstance().Register(*channel, this, mode);
      switch (outcome) {
        case RegistrationOutcome::kAdded:
          registered_channels_.push_back(*channel);
          result->Success();
          break;
        case RegistrationOutcome::kAlreadyRegistered:
          result->Success();
          break;
        case RegistrationOutcome::kLimitReached: {
          std::string message = mode == ChannelMode::kUnidirectional
                                    ? "channel " + *channel +
                                          " already registered in "
                                          "unidirectional mode"
                                    : "channel " + *channel +
                                          " already has the maximum number of "
                                          "registrations (2)";
          result->Error("CHANNEL_LIMIT_REACHED", message);
          break;
        }
        case RegistrationOutcome::kModeConflict:
          result->Error("CHANNEL_MODE_CONFLICT",
                        "channel " + *channel +
                            " is already registered in a different mode");
          break;
      }
    } else if (method == "unregisterMethodHandler") {
      auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("INVALID_ARGUMENTS", "arguments must be a map");
        return;
      }

      auto channel_it = args->find(flutter::EncodableValue("channel"));
      if (channel_it == args->end()) {
        result->Error("INVALID_ARGUMENTS", "channel is required");
        return;
      }

      auto* channel = std::get_if<std::string>(&channel_it->second);
      if (!channel) {
        result->Error("INVALID_ARGUMENTS", "channel must be a string");
        return;
      }

      ChannelRegistry::GetInstance().Unregister(*channel, this);

      auto it = std::find(registered_channels_.begin(),
                          registered_channels_.end(), *channel);
      if (it != registered_channels_.end()) {
        registered_channels_.erase(it);
      }

      result->Success();
    } else if (method == "invokeMethod") {
      auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("INVALID_ARGUMENTS", "arguments must be a map");
        return;
      }

      auto channel_it = args->find(flutter::EncodableValue("channel"));
      if (channel_it == args->end()) {
        result->Error("INVALID_ARGUMENTS", "channel is required");
        return;
      }

      auto* channel = std::get_if<std::string>(&channel_it->second);
      if (!channel) {
        result->Error("INVALID_ARGUMENTS", "channel must be a string");
        return;
      }

      auto* target = ChannelRegistry::GetInstance().GetTarget(*channel, this);
      if (target) {
        target->InvokeMethod(*channel, *call.arguments(), std::move(result));
      } else {
        std::string message;
        if (ChannelRegistry::GetInstance().HasRegistrations(*channel)) {
          message = "channel " + *channel +
                    " not accessible from this engine (may be bidirectional "
                    "pair or not registered)";
        } else {
          message = "unknown registered channel " + *channel;
        }
        result->Error("CHANNEL_UNREGISTERED", message);
      }
    } else {
      result->NotImplemented();
    }
  }

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<>> channel_;
  std::vector<std::string> registered_channels_;
};

}  // namespace

void WindowChannelPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<WindowChannelPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

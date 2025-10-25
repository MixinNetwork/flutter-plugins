#include "window_channel_plugin.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

enum class ChannelMode { kUnidirectional, kBidirectional };

enum class RegistrationOutcome {
  kAdded,
  kAlreadyRegistered,
  kLimitReached,
  kModeConflict
};

struct _WindowChannelPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  std::vector<std::string>* registered_channels;
};

G_DEFINE_TYPE(WindowChannelPlugin, window_channel_plugin, G_TYPE_OBJECT)

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

static void window_channel_plugin_dispose(GObject* object) {
  WindowChannelPlugin* self = (WindowChannelPlugin*)object;

  if (self->registered_channels) {
    for (const auto& channel : *self->registered_channels) {
      ChannelRegistry::GetInstance().Unregister(channel, self);
    }
    delete self->registered_channels;
    self->registered_channels = nullptr;
  }

  G_OBJECT_CLASS(window_channel_plugin_parent_class)->dispose(object);
}

static void window_channel_plugin_class_init(WindowChannelPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = window_channel_plugin_dispose;
}

static void window_channel_plugin_init(WindowChannelPlugin* self) {
  self->registered_channels = new std::vector<std::string>();
}

void window_channel_plugin_invoke_method(WindowChannelPlugin* self,
                                         const gchar* channel,
                                         FlValue* arguments,
                                         FlMethodCall* method_call) {
  // Check if this plugin has registered this channel
  auto it = std::find(self->registered_channels->begin(),
                      self->registered_channels->end(), std::string(channel));
  if (it == self->registered_channels->end()) {
    g_autofree gchar* error_msg =
        g_strdup_printf("channel %s not found in this engine", channel);
    fl_method_call_respond_error(method_call, "CHANNEL_NOT_FOUND", error_msg,
                                 nullptr, nullptr);
    return;
  }

  fl_method_channel_invoke_method(self->channel, "methodCall", arguments,
                                  nullptr,
                                  +[](GObject* source_object, GAsyncResult* res,
                                      gpointer user_data) {
                                    auto* call = (FlMethodCall*)user_data;
                                    GError* error = nullptr;
                                    auto* result = fl_method_channel_invoke_method_finish(
                                        FL_METHOD_CHANNEL(source_object), res,
                                        &error);
                                    if (error != nullptr) {
                                      fl_method_call_respond_error(
                                          call, "INVOKE_ERROR", error->message,
                                          nullptr, nullptr);
                                      g_error_free(error);
                                    } else {
                                      fl_method_call_respond(call, result,
                                                            nullptr);
                                    }
                                    g_object_unref(call);
                                  },
                                  g_object_ref(method_call));
}

static void handle_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  WindowChannelPlugin* self = (WindowChannelPlugin*)user_data;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "registerMethodHandler") == 0) {
    FlValue* channel_value = fl_value_lookup_string(args, "channel");
    if (channel_value == nullptr ||
        fl_value_get_type(channel_value) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS",
                                   "channel is required", nullptr, nullptr);
      return;
    }

    const gchar* channel_name = fl_value_get_string(channel_value);

    // Get mode (default to bidirectional)
    ChannelMode mode = ChannelMode::kBidirectional;
    FlValue* mode_value = fl_value_lookup_string(args, "mode");
    if (mode_value != nullptr &&
        fl_value_get_type(mode_value) == FL_VALUE_TYPE_STRING) {
      const gchar* mode_str = fl_value_get_string(mode_value);
      if (strcmp(mode_str, "unidirectional") == 0) {
        mode = ChannelMode::kUnidirectional;
      } else if (strcmp(mode_str, "bidirectional") == 0) {
        mode = ChannelMode::kBidirectional;
      } else {
        g_autofree gchar* error_msg = g_strdup_printf(
            "invalid mode: %s, must be 'unidirectional' or 'bidirectional'",
            mode_str);
        fl_method_call_respond_error(method_call, "INVALID_MODE", error_msg,
                                     nullptr, nullptr);
        return;
      }
    }

    auto outcome =
        ChannelRegistry::GetInstance().Register(channel_name, self, mode);

    switch (outcome) {
      case RegistrationOutcome::kAdded:
        self->registered_channels->push_back(channel_name);
        fl_method_call_respond_success(method_call, nullptr, nullptr);
        break;
      case RegistrationOutcome::kAlreadyRegistered:
        fl_method_call_respond_success(method_call, nullptr, nullptr);
        break;
      case RegistrationOutcome::kLimitReached: {
        g_autofree gchar* error_msg;
        if (mode == ChannelMode::kUnidirectional) {
          error_msg = g_strdup_printf(
              "channel %s already registered in unidirectional mode",
              channel_name);
        } else {
          error_msg = g_strdup_printf(
              "channel %s already has the maximum number of registrations (2)",
              channel_name);
        }
        fl_method_call_respond_error(method_call, "CHANNEL_LIMIT_REACHED",
                                     error_msg, nullptr, nullptr);
        break;
      }
      case RegistrationOutcome::kModeConflict: {
        g_autofree gchar* error_msg = g_strdup_printf(
            "channel %s is already registered in a different mode",
            channel_name);
        fl_method_call_respond_error(method_call, "CHANNEL_MODE_CONFLICT",
                                     error_msg, nullptr, nullptr);
        break;
      }
    }
  } else if (strcmp(method, "unregisterMethodHandler") == 0) {
    FlValue* channel_value = fl_value_lookup_string(args, "channel");
    if (channel_value == nullptr ||
        fl_value_get_type(channel_value) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS",
                                   "channel is required", nullptr, nullptr);
      return;
    }

    const gchar* channel_name = fl_value_get_string(channel_value);
    ChannelRegistry::GetInstance().Unregister(channel_name, self);

    auto it = std::find(self->registered_channels->begin(),
                        self->registered_channels->end(),
                        std::string(channel_name));
    if (it != self->registered_channels->end()) {
      self->registered_channels->erase(it);
    }

    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (strcmp(method, "invokeMethod") == 0) {
    FlValue* channel_value = fl_value_lookup_string(args, "channel");
    if (channel_value == nullptr ||
        fl_value_get_type(channel_value) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS",
                                   "channel is required", nullptr, nullptr);
      return;
    }

    const gchar* channel_name = fl_value_get_string(channel_value);
    auto* target = ChannelRegistry::GetInstance().GetTarget(channel_name, self);

    if (target) {
      window_channel_plugin_invoke_method(target, channel_name, args,
                                         method_call);
    } else {
      g_autofree gchar* error_msg;
      if (ChannelRegistry::GetInstance().HasRegistrations(channel_name)) {
        error_msg = g_strdup_printf(
            "channel %s not accessible from this engine (may be bidirectional "
            "pair or not registered)",
            channel_name);
      } else {
        error_msg =
            g_strdup_printf("unknown registered channel %s", channel_name);
      }
      fl_method_call_respond_error(method_call, "CHANNEL_UNREGISTERED",
                                   error_msg, nullptr, nullptr);
    }
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

void window_channel_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  WindowChannelPlugin* plugin = (WindowChannelPlugin*)g_object_new(
      window_channel_plugin_get_type(), nullptr);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "mixin.one/desktop_multi_window/channels", FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(plugin->channel, handle_method_call,
                                            plugin, g_object_unref);

  // Keep plugin alive - it will be cleaned up when the registrar is destroyed
  g_object_ref(plugin);
}

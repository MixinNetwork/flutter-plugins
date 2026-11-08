#include "include/desktop_webview_window/desktop_webview_window_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "webview_window.h"

#define WEBVIEW_WINDOW_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), webview_window_plugin_get_type(), \
                              WebviewWindowPlugin))

struct _WebviewWindowPlugin {
  GObject parent_instance;
  // Weak: the channel owns this plugin through its handler.
  FlMethodChannel *channel;
  std::map<int64_t, std::unique_ptr<WebviewWindow>> *windows;
};

G_DEFINE_TYPE(WebviewWindowPlugin, webview_window_plugin, g_object_get_type())

namespace {

constexpr char kChannel[] = "desktop_webview_window";

FlValue *Lookup(FlValue *args, const char *key) {
  return args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, key)
             : nullptr;
}

const char *String(FlValue *args, const char *key) {
  auto *value = Lookup(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

int64_t Int(FlValue *args, const char *key, int64_t fallback) {
  auto *value = Lookup(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value)
             : fallback;
}

bool Bool(FlValue *args, const char *key, bool fallback) {
  auto *value = Lookup(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL
             ? fl_value_get_bool(value)
             : fallback;
}

void Success(FlMethodCall *call, FlValue *value = nullptr) {
  fl_method_call_respond_success(call, value, nullptr);
}

void Error(FlMethodCall *call, const char *code, const char *message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

// Applies Dart's reply to a navigation WebKit is waiting on. Anything but an
// explicit false allows it.
void on_navigation_decided(GObject *object, GAsyncResult *result,
                           gpointer user_data) {
  g_autoptr(WebKitPolicyDecision) decision = WEBKIT_POLICY_DECISION(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, &error);
  FlValue *value = response != nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(response)
                       ? fl_method_success_response_get_result(
                             FL_METHOD_SUCCESS_RESPONSE(response))
                       : nullptr;
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
      !fl_value_get_bool(value)) {
    webkit_policy_decision_ignore(decision);
  } else {
    webkit_policy_decision_use(decision);
  }
}

void create_window(WebviewWindowPlugin *self, FlMethodCall *call) {
  FlValue *args = fl_method_call_get_args(call);
  WebviewWindow::Options options;
  const char *title = String(args, "title");
  options.title = title ? title : "";
  options.width = static_cast<int>(Int(args, "windowWidth", 1280));
  options.height = static_cast<int>(Int(args, "windowHeight", 720));
  options.x = static_cast<int>(Int(args, "windowPosX", 0));
  options.y = static_cast<int>(Int(args, "windowPosY", 0));
  options.use_position = Bool(args, "useWindowPositionAndSize", false);
  options.open_maximized = Bool(args, "openMaximized", false);
  options.open_hidden = Bool(args, "openHidden", false);
  options.title_bar = static_cast<uint32_t>(Int(args, "titleBar", 0xF));
  if (const char *arguments = String(args, "composerArguments")) {
    options.has_composer_arguments = true;
    options.composer_arguments = arguments;
  }
  const char *bridge = String(args, "javaScriptBridge");
  options.javascript_bridge = bridge ? bridge : "";

  const auto window_id = dww::NextBrowserId();
  auto *windows = self->windows;
  auto owned = std::make_unique<WebviewWindow>(
      [self](const char *method, FlValue *args) {
        if (self->channel == nullptr) return;
        fl_method_channel_invoke_method(self->channel, method, args, nullptr,
                                        nullptr, nullptr);
      },
      [self, window_id](const char *url, WebKitPolicyDecision *decision) {
        if (self->channel == nullptr) {
          webkit_policy_decision_use(decision);
          return;
        }
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "id", fl_value_new_int(window_id));
        fl_value_set_string_take(args, "url", fl_value_new_string(url));
        fl_method_channel_invoke_method(self->channel, "onUrlRequest", args,
                                        nullptr,
                                        on_navigation_decided,
                                        g_object_ref(decision));
      },
      window_id, [windows, window_id]() { windows->erase(window_id); },
      options);
  auto *window = owned.get();
  windows->insert({window_id, std::move(owned)});
  window->Start(options);

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "id", fl_value_new_int(window_id));
  if (window->IsClosing()) {
    // Closed from a composer callback: tear down before replying, so Dart
    // receives a browser that has already closed.
    window->DestroyNow();
    fl_value_set_string_take(result, "closed", fl_value_new_bool(true));
    fl_value_set_string_take(result, "windowHandle", fl_value_new_int(0));
  } else {
    fl_value_set_string_take(
        result, "windowHandle",
        fl_value_new_int(reinterpret_cast<intptr_t>(window->NativeWindow())));
  }
  Success(call, result);
}

void clear_all(WebviewWindowPlugin *self, FlMethodCall *call) {
  // Closing destroys each window synchronously and erases its map entry.
  // Iterate a snapshot, not an iterator invalidated by that callback.
  std::vector<int64_t> ids;
  for (const auto &item : *self->windows) ids.push_back(item.first);
  for (int64_t id : ids) {
    auto found = self->windows->find(id);
    if (found != self->windows->end()) found->second->Close();
  }
  // Clearing without any web view crashes some WebKit builds, so create a
  // temporary one to own the data manager.
  g_autoptr(WebKitWebView) web_view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  g_object_ref_sink(web_view);
  auto *context = webkit_web_view_get_context(web_view);
  webkit_website_data_manager_clear(
      webkit_web_context_get_website_data_manager(context),
      WEBKIT_WEBSITE_DATA_ALL, 0, nullptr, nullptr, nullptr);
  Success(call);
}

void handle_call(WebviewWindowPlugin *self, FlMethodCall *call) {
  if (self->windows == nullptr) {
    Error(call, "engine_detached", "The plugin was detached");
    return;
  }
  const char *method = fl_method_call_get_name(call);
  FlValue *args = fl_method_call_get_args(call);
  if (strcmp(method, "isWebviewAvailable") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    Success(call, result);
    return;
  }
  if (strcmp(method, "create") == 0) {
    create_window(self, call);
    return;
  }
  if (strcmp(method, "clearAll") == 0) {
    clear_all(self, call);
    return;
  }

  const int64_t window_id = Int(args, "viewId", -1);
  auto found = self->windows->find(window_id);
  if (strcmp(method, "close") == 0) {
    // A duplicated or delayed close is already satisfied.
    if (found != self->windows->end()) found->second->Close();
    Success(call);
    return;
  }
  if (found == self->windows->end()) {
    const std::string message =
        "No open browser with id " + std::to_string(window_id);
    Error(call, "browser_closed", message.c_str());
    return;
  }
  WebviewWindow *window = found->second.get();
  if (strcmp(method, "launch") == 0) {
    const char *url = String(args, "url");
    if (url == nullptr) {
      Error(call, "invalid_argument", "url is required");
      return;
    }
    window->Navigate(url, Bool(args, "triggerOnUrlRequestEvent", true));
    Success(call);
  } else if (strcmp(method, "setUrlRequestEnabled") == 0) {
    window->SetUrlRequestEnabled(Bool(args, "enabled", false));
    Success(call);
  } else if (strcmp(method, "addScriptToExecuteOnDocumentCreated") == 0) {
    const char *script = String(args, "javaScript");
    if (script == nullptr) {
      Error(call, "invalid_argument", "javaScript is required");
      return;
    }
    window->RunJavaScriptWhenContentReady(script);
    Success(call);
  } else if (strcmp(method, "setApplicationNameForUserAgent") == 0) {
    const char *name = String(args, "applicationName");
    if (name == nullptr) {
      Error(call, "invalid_argument", "applicationName is required");
      return;
    }
    window->SetApplicationNameForUserAgent(name);
    Success(call);
  } else if (strcmp(method, "back") == 0) {
    window->GoBack();
    Success(call);
  } else if (strcmp(method, "forward") == 0) {
    window->GoForward();
    Success(call);
  } else if (strcmp(method, "reload") == 0) {
    window->Reload();
    Success(call);
  } else if (strcmp(method, "stop") == 0) {
    window->Stop();
    Success(call);
  } else if (strcmp(method, "getAllCookies") == 0) {
    window->GetAllCookies(call);
  } else if (strcmp(method, "evaluateJavaScript") == 0) {
    const char *script = String(args, "javaScriptString");
    if (script == nullptr) {
      Error(call, "invalid_argument", "javaScriptString is required");
      return;
    }
    window->EvaluateJavaScript(script, call);
  } else if (strcmp(method, "postJavaScriptMessage") == 0) {
    // WebKit has no web-message API; the bridge dispatches a script instead.
    const char *script = String(args, "script");
    if (script == nullptr) {
      Error(call, "invalid_argument", "script is required");
      return;
    }
    window->EvaluateJavaScript(script, call);
  } else if (strcmp(method, "openDevToolsWindow") == 0) {
    window->OpenInspector();
    Success(call);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

}  // namespace

static void webview_window_plugin_dispose(GObject *object) {
  auto *self = WEBVIEW_WINDOW_PLUGIN(object);
  // Destructors deliver closing and disconnect native callbacks before
  // destroying GTK widgets.
  delete self->windows;
  self->windows = nullptr;
  if (self->channel != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(self->channel),
                                 reinterpret_cast<gpointer *>(&self->channel));
    self->channel = nullptr;
  }
  G_OBJECT_CLASS(webview_window_plugin_parent_class)->dispose(object);
}

static void webview_window_plugin_class_init(WebviewWindowPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = webview_window_plugin_dispose;
}

static void webview_window_plugin_init(WebviewWindowPlugin *self) {
  self->windows = new std::map<int64_t, std::unique_ptr<WebviewWindow>>();
}

void desktop_webview_window_plugin_register_with_registrar(
    FlPluginRegistrar *registrar) {
  WebviewWindowPlugin *plugin = WEBVIEW_WINDOW_PLUGIN(
      g_object_new(webview_window_plugin_get_type(), nullptr));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // The messenger keeps the channel alive for the engine's lifetime, and the
  // channel owns the plugin through the handler's destroy notify.
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kChannel, FL_METHOD_CODEC(codec));
  plugin->channel = channel;
  g_object_add_weak_pointer(G_OBJECT(channel),
                            reinterpret_cast<gpointer *>(&plugin->channel));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel *, FlMethodCall *call, gpointer user_data) {
        handle_call(WEBVIEW_WINDOW_PLUGIN(user_data), call);
      },
      plugin, g_object_unref);
}

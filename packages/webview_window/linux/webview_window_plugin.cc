#include "include/webview_window/webview_window_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <memory>
#include <cstring>
#include <map>

#include "webview_window.h"

namespace {

int64_t next_window_id_ = 0;

}

#define WEBVIEW_WINDOW_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), webview_window_plugin_get_type(), \
                              WebviewWindowPlugin))

struct _WebviewWindowPlugin {
  GObject parent_instance;
  FlMethodChannel *method_channel;
  std::map<int64_t, std::unique_ptr<WebviewWindow>> windows_;
};

G_DEFINE_TYPE(WebviewWindowPlugin, webview_window_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void webview_window_plugin_handle_method_call(
    WebviewWindowPlugin *self,
    FlMethodCall *method_call) {

  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "create") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(method_call, "0", "create args is not map", nullptr, nullptr);
      return;
    }
    auto width = fl_value_get_int(fl_value_lookup_string(args, "windowWidth"));
    auto height = fl_value_get_int(fl_value_lookup_string(args, "windowHeight"));
    auto title = fl_value_get_string(fl_value_lookup_string(args, "title"));

    auto window_id = next_window_id_;
    auto webview = std::make_unique<WebviewWindow>(self->method_channel, window_id, [&]() {
      self->windows_.erase(window_id);
    }, title, width, height);
    next_window_id_++;
    fl_method_call_respond_success(method_call, fl_value_new_int(window_id), nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }

}

static void webview_window_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(webview_window_plugin_parent_class)->dispose(object);
}

static void webview_window_plugin_class_init(WebviewWindowPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = webview_window_plugin_dispose;
}

static void webview_window_plugin_init(WebviewWindowPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  WebviewWindowPlugin *plugin = WEBVIEW_WINDOW_PLUGIN(user_data);
  webview_window_plugin_handle_method_call(plugin, method_call);
}

void webview_window_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  WebviewWindowPlugin *plugin = WEBVIEW_WINDOW_PLUGIN(
      g_object_new(webview_window_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "webview_window",
                            FL_METHOD_CODEC(codec));
  plugin->method_channel = channel;
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}

#include "include/desktop_lifecycle/desktop_lifecycle_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

static void dispatch_window_state(FlMethodChannel *fl_method_channel, bool active) {
  fl_method_channel_invoke_method(fl_method_channel, "onApplicationFocusChanged", fl_value_new_bool(active),
                                  nullptr, nullptr, nullptr);
}

static gboolean focus_in_event(
    GtkWidget *self,
    GdkEventFocus *event,
    gpointer user_data
) {
  dispatch_window_state(FL_METHOD_CHANNEL(user_data), event->in == TRUE);
  return false;
}

#define DESKTOP_LIFECYCLE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_lifecycle_plugin_get_type(), \
                              DesktopLifecyclePlugin))

struct _DesktopLifecyclePlugin {
  GObject parent_instance;
  FlMethodChannel *channel;
};

G_DEFINE_TYPE(DesktopLifecyclePlugin, desktop_lifecycle_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void desktop_lifecycle_plugin_handle_method_call(
    DesktopLifecyclePlugin *self,
    FlMethodCall *method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "init") == 0) {
    dispatch_window_state(self->channel, true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void desktop_lifecycle_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(desktop_lifecycle_plugin_parent_class)->dispose(object);
}

static void desktop_lifecycle_plugin_class_init(DesktopLifecyclePluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_lifecycle_plugin_dispose;
}

static void desktop_lifecycle_plugin_init(DesktopLifecyclePlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  DesktopLifecyclePlugin *plugin = DESKTOP_LIFECYCLE_PLUGIN(user_data);
  desktop_lifecycle_plugin_handle_method_call(plugin, method_call);
}

void desktop_lifecycle_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  DesktopLifecyclePlugin *plugin = DESKTOP_LIFECYCLE_PLUGIN(
      g_object_new(desktop_lifecycle_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel *channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "desktop_lifecycle",
                            FL_METHOD_CODEC(codec));
  plugin->channel = channel;
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  auto fl_view = GTK_WIDGET(fl_plugin_registrar_get_view(registrar));

  g_signal_connect(GTK_WIDGET(fl_view), "focus-in-event",
                   G_CALLBACK(focus_in_event), channel);
  g_signal_connect(GTK_WIDGET(fl_view), "focus-out-event",
                   G_CALLBACK(focus_in_event), channel);

  g_object_unref(plugin);
}

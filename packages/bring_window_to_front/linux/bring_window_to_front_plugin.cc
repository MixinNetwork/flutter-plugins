#include "include/bring_window_to_front/bring_window_to_front_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#define BRING_WINDOW_TO_FRONT_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), bring_window_to_front_plugin_get_type(), \
                              BringWindowToFrontPlugin))

struct _BringWindowToFrontPlugin {
  GObject parent_instance;
  GtkWindow *window;
};

G_DEFINE_TYPE(BringWindowToFrontPlugin, bring_window_to_front_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void bring_window_to_front_plugin_handle_method_call(
    BringWindowToFrontPlugin *self,
    FlMethodCall *method_call) {
  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "bringToFront") == 0) {
    if (self->window) {
      // gtk_window_present does not work on Wayland.
      // Use gtk_present_with_time as a workaround instead.
      // See https://gitlab.gnome.org/GNOME/gtk/issues/624#note_10996
      gtk_window_present_with_time(
          self->window,
          g_get_monotonic_time() / 1000);
    } else {
      g_warning("failed to bring to front: not window set");
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void bring_window_to_front_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(bring_window_to_front_plugin_parent_class)->dispose(object);
}

static void bring_window_to_front_plugin_class_init(BringWindowToFrontPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = bring_window_to_front_plugin_dispose;
}

static void bring_window_to_front_plugin_init(BringWindowToFrontPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  BringWindowToFrontPlugin *plugin = BRING_WINDOW_TO_FRONT_PLUGIN(user_data);
  bring_window_to_front_plugin_handle_method_call(plugin, method_call);
}

void bring_window_to_front_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  BringWindowToFrontPlugin *plugin = BRING_WINDOW_TO_FRONT_PLUGIN(
      g_object_new(bring_window_to_front_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "bring_window_to_front",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view) {
    plugin->window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }

  g_object_unref(plugin);
}

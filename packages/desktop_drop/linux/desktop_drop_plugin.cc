#include "include/desktop_drop/desktop_drop_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <stdlib.h>
#include <sys/utsname.h>

#define DESKTOP_DROP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_drop_plugin_get_type(), \
                              DesktopDropPlugin))

struct _DesktopDropPlugin {
  GObject parent_instance;
};

static gboolean isKDE = FALSE;
static gboolean ignoreNext = FALSE;

G_DEFINE_TYPE(DesktopDropPlugin, desktop_drop_plugin, g_object_get_type())

void on_drag_data_received(GtkWidget *widget, GdkDragContext *drag_context,
                           gint x, gint y, GtkSelectionData *sdata, guint info,
                           guint time, gpointer user_data) {
  // When dragging from different file managers we may receive a plain string
  // (e.g. "dde-fileManager") instead of real URIs.  Use gtk_selection_data_get_uris
  // which understands the "text/uri-list" format and returns an array of
  // URI strings.  Convert those to local filenames and join with newlines.
  auto *channel = static_cast<FlMethodChannel *>(user_data);
  double point[] = {double(x), double(y)};

  gchar *text = nullptr;
  gchar **uris = gtk_selection_data_get_uris(sdata);
  if (uris) {
    // build newline-separated list of file paths
    GString *builder = g_string_new(NULL);
    for (gchar **uri = uris; *uri; uri++) {
      gchar *filename = g_filename_from_uri(*uri, nullptr, nullptr);
      if (!filename) {
        // if conversion failed, fall back to raw URI
        filename = g_strdup(*uri);
      }
      if (builder->len > 0) {
        g_string_append(builder, "\n");
      }
      g_string_append(builder, filename);
      g_free(filename);
    }
    text = g_string_free(builder, FALSE);
    g_strfreev(uris);
  } else {
    // fallback to the raw data as before
    auto *data = gtk_selection_data_get_data(sdata);
    if (data) {
      text = g_strdup((gchar *)data);
    }
  }

  if (!text) {
    text = g_strdup("");
  }

  auto args = fl_value_new_list();
  fl_value_append(args, fl_value_new_string(text));
  fl_value_append(args, fl_value_new_float_list(point, 2));
  fl_method_channel_invoke_method(channel, "performOperation_linux", args,
                                  nullptr, nullptr, nullptr);
  g_free(text);
}

void on_drag_motion(GtkWidget *widget, GdkDragContext *drag_context,
                    gint x, gint y, guint time, gpointer user_data) {
  if (ignoreNext) {
    ignoreNext = FALSE;
    return;
  }

  auto *channel = static_cast<FlMethodChannel *>(user_data);
  double point[] = {double(x), double(y)};
  g_autoptr(FlValue) args = fl_value_new_float_list(point, 2);
  fl_method_channel_invoke_method(channel, "updated", args,
                                  nullptr, nullptr, nullptr);
}

void on_drag_leave(GtkWidget *widget, GdkDragContext *drag_context, guint time, gpointer user_data) {
  auto *channel = static_cast<FlMethodChannel *>(user_data);
  fl_method_channel_invoke_method(channel, "exited", nullptr,
                                  nullptr, nullptr, nullptr);
}

// Called when a method call is received from Flutter.
static void desktop_drop_plugin_handle_method_call(
    DesktopDropPlugin *self,
    FlMethodCall *method_call) {
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

static void desktop_drop_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(desktop_drop_plugin_parent_class)->dispose(object);
}

static void desktop_drop_plugin_class_init(DesktopDropPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_drop_plugin_dispose;
}

static void desktop_drop_plugin_init(DesktopDropPlugin *self) {
  const char * desktopEnv = getenv("XDG_CURRENT_DESKTOP");
  if (desktopEnv) {
    const char * lowercaseDesktopEnv = g_ascii_strdown(desktopEnv, -1);

    if (strcmp(lowercaseDesktopEnv, "kde") == 0 || strcmp(lowercaseDesktopEnv, "plasma") == 0) {
        isKDE = TRUE;
    }
  }
}

static gboolean on_focus_in_event(GtkWidget *widget, GdkEventFocus *event, gpointer user_data) {
  if (isKDE) {
    ignoreNext = TRUE;
  }
  return FALSE;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  DesktopDropPlugin *plugin = DESKTOP_DROP_PLUGIN(user_data);
  desktop_drop_plugin_handle_method_call(plugin, method_call);
}

void desktop_drop_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  DesktopDropPlugin *plugin = DESKTOP_DROP_PLUGIN(
      g_object_new(desktop_drop_plugin_get_type(), nullptr));

  auto *fl_view = fl_plugin_registrar_get_view(registrar);
  // Use URI targets for file drops and avoid forcing the generic STRING
  // target first.  Prioritize text/uri-list so we receive actual file
  // URIs instead of application names like "dde-fileManager".
  gtk_drag_dest_set(GTK_WIDGET(fl_view), GTK_DEST_DEFAULT_ALL, nullptr, 0, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(GTK_WIDGET(fl_view));
  // In case a source doesn't provide URI targets we still accept generic
  // text, but it is added _after_ the URI targets so it has lower priority.
  gtk_drag_dest_add_text_targets(GTK_WIDGET(fl_view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel *channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "desktop_drop",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_signal_connect(fl_view, "drag-motion",
                   G_CALLBACK(on_drag_motion), channel);
  g_signal_connect(GTK_WIDGET(fl_view), "drag-data-received",
                   G_CALLBACK(on_drag_data_received), channel);
  g_signal_connect(GTK_WIDGET(fl_view), "drag-leave",
                   G_CALLBACK(on_drag_leave), channel);
  g_signal_connect(fl_view, "focus-in-event",
                   G_CALLBACK(on_focus_in_event), nullptr);

  g_object_unref(plugin);
}

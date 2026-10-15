#include "include/desktop_drop/desktop_drop_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string>

#define DESKTOP_DROP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_drop_plugin_get_type(), \
                              DesktopDropPlugin))

struct _DesktopDropPlugin {
    GObject parent_instance;
};

static gboolean isKDE = FALSE;
static gboolean ignoreNext = FALSE;

G_DEFINE_TYPE(DesktopDropPlugin, desktop_drop_plugin, g_object_get_type())

namespace {
    constexpr char kPortalTarget[] = "application/vnd.portal.filetransfer";
    constexpr char kUriTarget[] = "text/uri-list";
    constexpr char kDropPosition[] = "renamer-desktop-drop-position";

    struct DropPosition {
        gint x;
        gint y;
        guint time;
    };

// Own everything used by the asynchronous D-Bus callbacks. Selection data and
// the signal arguments themselves are only borrowed for the signal's duration.
    struct PendingDrop {
        GtkWidget *widget;
        GdkDragContext *context;
        FlMethodChannel *channel;
        DropPosition position;
        std::string key;

        PendingDrop(GtkWidget *widget, GdkDragContext *context,
                    FlMethodChannel *channel, DropPosition position)
                : widget(static_cast<GtkWidget *>(g_object_ref(widget))),
                  context(static_cast<GdkDragContext *>(g_object_ref(context))),
                  channel(static_cast<FlMethodChannel *>(g_object_ref(channel))),
                  position(position) {}

        ~PendingDrop() {
          g_object_unref(channel);
          g_object_unref(context);
          g_object_unref(widget);
        }
    };

    void finish_drop(PendingDrop *drop, gboolean success) {
      g_object_set_data(G_OBJECT(drop->context), kDropPosition, nullptr);
      // The plugin advertises COPY, never a request to delete the source files.
      gtk_drag_finish(drop->context, success, FALSE, drop->position.time);
      delete drop;
    }

    void deliver_uris(PendingDrop *drop, const gchar *text) {
      // Do not let comments, empty selections or a portal key become file paths.
      g_auto(GStrv) uris = g_uri_list_extract_uris(text);
      g_autoptr(GString) valid_uris = g_string_new(nullptr);
      for (gchar **uri = uris; uri && *uri; ++uri) {
        g_autofree gchar *scheme = g_uri_parse_scheme(*uri);
        if (scheme) {
          g_string_append(valid_uris, *uri);
          g_string_append(valid_uris, "\r\n");
        }
      }
      if (valid_uris->len == 0) {
        finish_drop(drop, FALSE);
        return;
      }

      double point[] = {double(drop->position.x), double(drop->position.y)};
      g_autoptr(FlValue) args = fl_value_new_list();
      fl_value_append_take(args, fl_value_new_string(valid_uris->str));
      fl_value_append_take(args, fl_value_new_float_list(point, 2));
      // Preserve rawText's public contract even though paths are now resolved here.
      fl_value_append_take(
              args, fl_value_new_string(drop->key.empty() ? text : drop->key.c_str()));
      // Reuse desktop_drop's URI decoding and DropDoneEvent, including coordinates.
      // Dart must not retrieve the one-time portal key a second time.
      fl_method_channel_invoke_method(drop->channel, "performOperation_linux", args,
                                      nullptr, nullptr, nullptr);
      finish_drop(drop, TRUE);
    }

    void fallback_to_uris(PendingDrop *drop) {
      GdkAtom target = gdk_atom_intern_static_string(kUriTarget);
      if (g_list_find(gdk_drag_context_list_targets(drop->context), target)) {
        // Keep the drag alive until the fallback selection has been received.
        gtk_drag_get_data(drop->widget, drop->context, target, drop->position.time);
        delete drop;
      } else {
        finish_drop(drop, FALSE);
      }
    }

    void portal_files_received(GObject *source, GAsyncResult *result,
                               gpointer user_data) {
      auto *drop = static_cast<PendingDrop *>(user_data);
      g_autoptr(GError) error = nullptr;
      g_autoptr(GVariant) reply =
                                  g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
      if (!reply) {
        g_message("desktop_drop: portal transfer failed, trying URI list: %s",
                  error->message);
        fallback_to_uris(drop);
        return;
      }

      g_auto(GStrv) paths = nullptr;
      g_variant_get(reply, "(^as)", &paths);
      g_autoptr(GString) uris = g_string_new(nullptr);
      for (gchar **path = paths; path && *path; ++path) {
        g_autofree gchar *uri = g_filename_to_uri(*path, nullptr, nullptr);
        if (uri) {
          g_string_append(uris, uri);
          g_string_append(uris, "\r\n");
        }
      }
      if (uris->len == 0) {
        fallback_to_uris(drop);
        return;
      }
      deliver_uris(drop, uris->str);
    }

    void portal_bus_ready(GObject *source, GAsyncResult *result,
                          gpointer user_data) {
      auto *drop = static_cast<PendingDrop *>(user_data);
      g_autoptr(GError) error = nullptr;
      g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
      if (!bus) {
        fallback_to_uris(drop);
        return;
      }
      g_dbus_connection_call(
              bus, "org.freedesktop.portal.Documents",
              "/org/freedesktop/portal/documents",
              "org.freedesktop.portal.FileTransfer", "RetrieveFiles",
              g_variant_new("(s@a{sv})", drop->key.c_str(),
                            g_variant_new_array(G_VARIANT_TYPE("{sv}"), nullptr, 0)),
              G_VARIANT_TYPE("(as)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
              portal_files_received, drop);
    }

    void receive_drop(PendingDrop *drop, GdkAtom target, const guchar *data,
                      gint length) {
      const bool portal = target == gdk_atom_intern_static_string(kPortalTarget);
      if (length <= 0 || !data) {
        if (portal) {
          fallback_to_uris(drop);
        } else {
          finish_drop(drop, FALSE);
        }
        return;
      }
      // GTK does not promise a trailing NUL. Copy only the supplied byte length.
      g_autofree gchar *payload =
              g_strndup(reinterpret_cast<const gchar *>(data), length);
      if (!g_utf8_validate(payload, -1, nullptr) || payload[0] == '\0') {
        if (portal) {
          fallback_to_uris(drop);
        } else {
          finish_drop(drop, FALSE);
        }
        return;
      }
      if (portal) {
        drop->key = payload;
        g_bus_get(G_BUS_TYPE_SESSION, nullptr, portal_bus_ready, drop);
      } else {
        deliver_uris(drop, payload);
      }
    }

    void configure_drag_destination(GtkWidget *widget) {
      static GtkTargetEntry entries[] = {
              {const_cast<gchar *>(kPortalTarget), GTK_TARGET_OTHER_APP, 0},
              {const_cast<gchar *>(kUriTarget), GTK_TARGET_OTHER_APP, 0},
              {const_cast<gchar *>("STRING"), GTK_TARGET_OTHER_APP, 0},
      };
      // GTK_DEST_DEFAULT_DROP would finish the drag as soon as the selection
      // callback returns, invalidating portal keys before RetrieveFiles completes.
      gtk_drag_dest_set(widget,
                        static_cast<GtkDestDefaults>(GTK_DEST_DEFAULT_MOTION |
                                                     GTK_DEST_DEFAULT_HIGHLIGHT),
                        entries, G_N_ELEMENTS(entries), GDK_ACTION_COPY);
    }

} // namespace

void on_drag_data_received(GtkWidget *widget, GdkDragContext *context,
                           gint x, gint y, GtkSelectionData *data, guint info,
                           guint time, gpointer user_data) {
  auto *position = static_cast<DropPosition *>(
          g_object_get_data(G_OBJECT(context), kDropPosition));
  // Ignore data requested for hover inspection by another handler.
  if (!position)
    return;
  auto *channel = static_cast<FlMethodChannel *>(user_data);
  receive_drop(new PendingDrop(widget, context, channel, *position),
               gtk_selection_data_get_target(data),
               gtk_selection_data_get_data(data),
               gtk_selection_data_get_length(data));
}

gboolean on_drag_drop(GtkWidget *widget, GdkDragContext *context, gint x,
                      gint y, guint time, gpointer user_data) {
  GdkAtom target = gtk_drag_dest_find_target(widget, context, nullptr);
  if (target == GDK_NONE)
    return FALSE;
  g_object_set_data_full(
          G_OBJECT(context), kDropPosition, new DropPosition{x, y, time},
          [](gpointer data) { delete static_cast<DropPosition *>(data); });
  gtk_drag_get_data(widget, context, target, time);
  return TRUE;
}

gboolean on_drag_motion(GtkWidget *widget, GdkDragContext *drag_context,
                        gint x, gint y, guint time, gpointer user_data) {
  if (ignoreNext) {
    ignoreNext = FALSE;
    return FALSE;
  }

  auto *channel = static_cast<FlMethodChannel *>(user_data);
  double point[] = {double(x), double(y)};
  g_autoptr(FlValue) args = fl_value_new_float_list(point, 2);
  fl_method_channel_invoke_method(channel, "updated", args,
                                  nullptr, nullptr, nullptr);
  return FALSE;
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
    g_autofree gchar * lowercaseDesktopEnv = g_ascii_strdown(desktopEnv, -1);

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
  configure_drag_destination(GTK_WIDGET(fl_view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel *channel =
          fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                "desktop_drop",
                                FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_signal_connect(fl_view, "drag-drop", G_CALLBACK(on_drag_drop), channel);
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

#include "include/pasteboard/pasteboard_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <vector>

#define GNOME_COPIED_FILES gdk_atom_intern_static_string ("x-special/gnome-copied-files")

#define PASTEBOARD_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pasteboard_plugin_get_type(), \
                              PasteboardPlugin))

struct _PasteboardPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(PasteboardPlugin, pasteboard_plugin, g_object_get_type())

static void gtk_clipboard_request_uris_callback(
    GtkClipboard *clipboard,
    gchar **uris,
    gpointer user_data
) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);

  g_autoptr(FlValue) result = fl_value_new_list();
  for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_autoptr(GFile) file = g_file_new_for_uri(*uri);
    auto *file_path = g_file_get_path(file);
    if (file_path) {
      fl_value_append(result, fl_value_new_string(file_path));
    }
  }
  fl_method_call_respond_success(method_call, result, nullptr);
}

static void gtk_clipboard_get_file_uri(GtkClipboard *clipboard,
                                       GtkSelectionData *selection_data,
                                       guint info,
                                       gpointer user_data_or_owner) {
  auto target = gtk_selection_data_get_target(selection_data);
  auto **uris = reinterpret_cast<gchar **>(user_data_or_owner);
  if (gtk_targets_include_uri(&target, 1)) {
    gtk_selection_data_set_uris(selection_data, reinterpret_cast<gchar **>(user_data_or_owner));
  } else if (gtk_targets_include_text(&target, 1)) {
    g_autoptr(GString) string = g_string_new(nullptr);
    bool should_insert_new_line = false;
    for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
      if (should_insert_new_line) {
        g_string_append_c(string, '\n');
      }
      g_string_append(string, *uri);
      should_insert_new_line = true;
    }
    gtk_selection_data_set_text(selection_data, string->str, int(string->len));
  } else if (target == GNOME_COPIED_FILES) {
    g_autoptr(GString) string = g_string_new("copy");
    for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
      g_string_append(string, "\n");
      g_string_append(string, *uri);
    }
    gtk_selection_data_set(selection_data, target, 8, (const guchar *) string->str, int(string->len));
  } else {
    g_critical("unsupported action: gdk_atom_name(target) = %s", gdk_atom_name(target));
  }

}

static void gtk_clipboard_clear(GtkClipboard *clipboard,
                                gpointer user_data_or_owner) {
  auto **uris = reinterpret_cast<gchar **>(user_data_or_owner);
  delete[] uris;
}

static void clipboard_request_image_callback(
    GtkClipboard *clipboard,
    GdkPixbuf *pixbuf,
    gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);

  if (!pixbuf) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  gchar *buffer = nullptr;
  gsize buffer_size = 0;
  GError *error = nullptr;

  gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, "png", &error, nullptr);
  if (error) {
    fl_method_call_respond_error(method_call, "0", error->message, nullptr, nullptr);
    return;
  }

  if (!buffer) {
    fl_method_call_respond_error(method_call, "0", "failed to get image", nullptr, nullptr);
    return;
  }

  fl_method_call_respond_success(method_call,
                                 fl_value_new_uint8_list(reinterpret_cast<const uint8_t *>(buffer), buffer_size),
                                 nullptr);

}

// Called when a method call is received from Flutter.
static void pasteboard_plugin_handle_method_call(
    PasteboardPlugin *self,
    FlMethodCall *method_call) {
  const gchar *method = fl_method_call_get_name(method_call);
  if (strcmp(method, "files") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
    gtk_clipboard_request_uris(clipboard, gtk_clipboard_request_uris_callback, g_object_ref(method_call));
  } else if (strcmp(method, "writeFiles") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());

    auto args = fl_method_call_get_args(method_call);
    auto size = fl_value_get_length(args);

    auto **paths = new gchar *[size + 1];
    paths[size] = nullptr;
    for (unsigned int i = 0; i < size; ++i) {
      auto path = fl_value_get_string(fl_value_get_list_value(args, i));
      paths[i] = g_strconcat("file://", path, nullptr);
    }

    GtkTargetList *target_list = gtk_target_list_new(nullptr, 0);
    gtk_target_list_add(target_list, GNOME_COPIED_FILES, 0, 0);

    gtk_target_list_add_uri_targets(target_list, 0);
    gtk_target_list_add_text_targets(target_list, 0);

    int n_targets = 1;
    GtkTargetEntry *target_table = gtk_target_table_new_from_list(target_list, &n_targets);

    gtk_clipboard_set_with_data(clipboard,
                                target_table,
                                n_targets,
                                gtk_clipboard_get_file_uri,
                                gtk_clipboard_clear,
                                paths);

    gtk_target_list_unref(target_list);
    gtk_target_table_free(target_table, n_targets);

    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (strcmp(method, "image") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());

    gtk_clipboard_request_image(clipboard, clipboard_request_image_callback, g_object_ref(method_call));

  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void pasteboard_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(pasteboard_plugin_parent_class)->dispose(object);
}

static void pasteboard_plugin_class_init(PasteboardPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = pasteboard_plugin_dispose;
}

static void pasteboard_plugin_init(PasteboardPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  PasteboardPlugin *plugin = PASTEBOARD_PLUGIN(user_data);
  pasteboard_plugin_handle_method_call(plugin, method_call);
}

void pasteboard_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  PasteboardPlugin *plugin = PASTEBOARD_PLUGIN(
      g_object_new(pasteboard_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "pasteboard",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}

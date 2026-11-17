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

// Collects the local paths of the given URIs, skipping any without one.
static FlValue *paths_from_uris(gchar **uris) {
  FlValue *paths = fl_value_new_list();
  for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_autoptr(GFile) file = g_file_new_for_uri(*uri);
    g_autofree gchar *file_path = g_file_get_path(file);
    if (file_path) {
      fl_value_append_take(paths, fl_value_new_string(file_path));
    }
  }
  return paths;
}

// State for a files() request, which tries each advertised target in order of
// preference until one of them yields usable file paths.
struct FilesRequest {
  FlMethodCall *method_call;
  std::vector<GdkAtom> targets;
  size_t next_target = 0;
};

static void files_request_free(FilesRequest *request) {
  g_object_unref(request->method_call);
  delete request;
}

static void files_request_try_next_target(GtkClipboard *clipboard,
                                          FilesRequest *request);

static void gtk_clipboard_files_received_callback(
    GtkClipboard *clipboard,
    GtkSelectionData *selection_data,
    gpointer user_data
) {
  auto *request = static_cast<FilesRequest *>(user_data);

  // For the FileTransfer portal's targets, this retrieves the files from the
  // portal, which makes them accessible inside the sandbox. It returns nullptr
  // when GTK cannot decode the target or the portal fails to retrieve the
  // files, in which case the next advertised target is tried instead.
  g_auto(GStrv) uris = gtk_selection_data_get_uris(selection_data);
  g_autoptr(FlValue) paths = paths_from_uris(uris);
  if (fl_value_get_length(paths) > 0) {
    fl_method_call_respond_success(request->method_call, paths, nullptr);
    files_request_free(request);
    return;
  }

  files_request_try_next_target(clipboard, request);
}

static void files_request_try_next_target(GtkClipboard *clipboard,
                                          FilesRequest *request) {
  if (request->next_target >= request->targets.size()) {
    g_autoptr(FlValue) paths = fl_value_new_list();
    fl_method_call_respond_success(request->method_call, paths, nullptr);
    files_request_free(request);
    return;
  }

  auto target = request->targets[request->next_target++];
  gtk_clipboard_request_contents(clipboard, target,
                                 gtk_clipboard_files_received_callback,
                                 request);
}

// Inside a Flatpak, the paths in text/uri-list are usually not accessible, so
// files are received through the FileTransfer portal when the source offers it.
// Outside of one, retrieving files from the portal fails, but some sources
// (like Dolphin) offer it anyway, so text/uri-list is used there instead.
static void gtk_clipboard_request_files_targets_callback(
    GtkClipboard *clipboard,
    GdkAtom *targets,
    gint n_targets,
    gpointer user_data
) {
  static const gchar *sandboxed_targets[] = {
      "application/vnd.portal.filetransfer",
      "application/vnd.portal.files",
      "text/uri-list",
      nullptr,
  };
  static const gchar *unsandboxed_targets[] = {
      "text/uri-list",
      nullptr,
  };

  auto *request = new FilesRequest();
  request->method_call = static_cast<FlMethodCall *>(user_data);

  const gboolean sandboxed = g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS);
  for (auto name = sandboxed ? sandboxed_targets : unsandboxed_targets;
       *name != nullptr; name++) {
    auto target = gdk_atom_intern_static_string(*name);
    for (gint i = 0; i < n_targets; i++) {
      if (targets[i] == target) {
        request->targets.push_back(target);
        break;
      }
    }
  }

  files_request_try_next_target(clipboard, request);
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
  g_strfreev(reinterpret_cast<gchar **>(user_data_or_owner));
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

  g_autofree gchar *buffer = nullptr;
  gsize buffer_size = 0;
  g_autoptr(GError) error = nullptr;

  gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, "png", &error, nullptr);
  if (error) {
    fl_method_call_respond_error(method_call, "0", error->message, nullptr, nullptr);
    return;
  }

  if (!buffer) {
    fl_method_call_respond_error(method_call, "0", "failed to get image", nullptr, nullptr);
    return;
  }

  g_autoptr(FlValue) result =
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t *>(buffer), buffer_size);
  fl_method_call_respond_success(method_call, result, nullptr);

}

// Called when a method call is received from Flutter.
static void pasteboard_plugin_handle_method_call(
    PasteboardPlugin *self,
    FlMethodCall *method_call) {
  const gchar *method = fl_method_call_get_name(method_call);
  if (strcmp(method, "files") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
    gtk_clipboard_request_targets(clipboard, gtk_clipboard_request_files_targets_callback,
                                  g_object_ref(method_call));
  } else if (strcmp(method, "writeFiles") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());

    auto args = fl_method_call_get_args(method_call);
    auto size = fl_value_get_length(args);

    auto **paths = g_new(gchar *, size + 1);
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

#include "include/desktop_multi_window/desktop_multi_window_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "multi_window_manager.h"
#include "desktop_multi_window_plugin_internal.h"

#define DESKTOP_MULTI_WINDOW_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_multi_window_plugin_get_type(), \
                              DesktopMultiWindowPlugin))

struct _DesktopMultiWindowPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(DesktopMultiWindowPlugin, desktop_multi_window_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void desktop_multi_window_plugin_handle_method_call(
    DesktopMultiWindowPlugin *self,
    FlMethodCall *method_call) {
  g_autoptr(FlMethodResponse) response;

  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "createWindow") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto *arguments = fl_value_get_string(args);
    auto window = MultiWindowManager::Instance()->Create(arguments);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(window)));
  } else if (strcmp(method, "show") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(args);
    MultiWindowManager::Instance()->Show(window_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "hide") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(args);
    MultiWindowManager::Instance()->Hide(window_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "close") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(args);
    MultiWindowManager::Instance()->Close(window_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "center") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(args);
    MultiWindowManager::Instance()->Center(window_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setFrame") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(fl_value_lookup_string(args, "windowId"));
    auto left = fl_value_get_float(fl_value_lookup_string(args, "left"));
    auto top = fl_value_get_float(fl_value_lookup_string(args, "top"));
    auto width = fl_value_get_float(fl_value_lookup_string(args, "width"));
    auto height = fl_value_get_float(fl_value_lookup_string(args, "height"));
    MultiWindowManager::Instance()->SetFrame(window_id, left, top, width, height);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setTitle") == 0) {
    auto *args = fl_method_call_get_args(method_call);
    auto window_id = fl_value_get_int(fl_value_lookup_string(args, "windowId"));
    auto title = fl_value_get_string(fl_value_lookup_string(args, "title"));
    MultiWindowManager::Instance()->SetTitle(window_id, title);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getAllSubWindowIds") == 0) {
    auto window_ids = MultiWindowManager::Instance()->GetAllSubWindowIds();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int64_list(window_ids.data(), window_ids.size())));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void desktop_multi_window_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(desktop_multi_window_plugin_parent_class)->dispose(object);
}

static void desktop_multi_window_plugin_class_init(DesktopMultiWindowPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_multi_window_plugin_dispose;
}

static void desktop_multi_window_plugin_init(DesktopMultiWindowPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  DesktopMultiWindowPlugin *plugin = DESKTOP_MULTI_WINDOW_PLUGIN(user_data);
  desktop_multi_window_plugin_handle_method_call(plugin, method_call);
}

void desktop_multi_window_plugin_register_with_registrar_internal(FlPluginRegistrar *registrar) {
  DesktopMultiWindowPlugin *plugin = DESKTOP_MULTI_WINDOW_PLUGIN(
      g_object_new(desktop_multi_window_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "mixin.one/flutter_multi_window",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}

void desktop_multi_window_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  desktop_multi_window_plugin_register_with_registrar_internal(registrar);
  auto view = fl_plugin_registrar_get_view(registrar);
  auto window = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (GTK_IS_WINDOW(window)) {
    auto window_channel = WindowChannel::RegisterWithRegistrar(registrar, 0);
    MultiWindowManager::Instance()->AttachMainWindow(window, std::move(window_channel));
  } else {
    g_critical("can not find GtkWindow instance for main window.");
  }
}

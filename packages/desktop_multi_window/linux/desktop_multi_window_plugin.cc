#include "include/desktop_multi_window/desktop_multi_window_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "desktop_multi_window_plugin_internal.h"
#include "flutter_window.h"
#include "multi_window_manager.h"
#include "window_channel_plugin.h"

#define DESKTOP_MULTI_WINDOW_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_multi_window_plugin_get_type(), \
                              DesktopMultiWindowPlugin))

struct _DesktopMultiWindowPlugin {
  GObject parent_instance;
  FlutterWindow* window;
};

G_DEFINE_TYPE(DesktopMultiWindowPlugin,
              desktop_multi_window_plugin,
              g_object_get_type())

// Called when a method call is received from Flutter.
static void desktop_multi_window_plugin_handle_method_call(
    DesktopMultiWindowPlugin* self,
    FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  // Check if this is a window-specific method (starts with "window_")
  if (g_str_has_prefix(method, "window_")) {
    auto* args = fl_method_call_get_args(method_call);
    auto window_id_value = fl_value_lookup_string(args, "windowId");
    if (window_id_value == nullptr) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("-1", "windowId is required", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    
    const gchar* window_id = fl_value_get_string(window_id_value);
    auto window = MultiWindowManager::Instance()->GetWindow(window_id);
    if (!window) {
      g_autofree gchar* error_msg =
          g_strdup_printf("failed to find target window: %s", window_id);
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("-1", error_msg, nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    
    window->HandleWindowMethod(method, args, method_call);
    return;  // Window handles the response
  }

  g_autoptr(FlMethodResponse) response = nullptr;
  
  if (strcmp(method, "createWindow") == 0) {
    auto* args = fl_method_call_get_args(method_call);
    auto window_id = MultiWindowManager::Instance()->Create(args);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string(window_id.c_str())));
  } else if (strcmp(method, "getWindowDefinition") == 0) {
    auto window_id = self->window->GetWindowId();
    auto window_argument = self->window->GetWindowArgument();

    g_autoptr(FlValue) definition = fl_value_new_map();
    fl_value_set_string_take(definition, "windowId",
                             fl_value_new_string(window_id.c_str()));
    fl_value_set_string_take(definition, "windowArgument",
                             fl_value_new_string(window_argument.c_str()));

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(definition));
  } else if (strcmp(method, "getAllWindows") == 0) {
    auto windows = MultiWindowManager::Instance()->GetAllWindows();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(windows));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void desktop_multi_window_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(desktop_multi_window_plugin_parent_class)->dispose(object);
}

static void desktop_multi_window_plugin_class_init(
    DesktopMultiWindowPluginClass
* klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_multi_window_plugin_dispose;
}

static void desktop_multi_window_plugin_init(DesktopMultiWindowPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  DesktopMultiWindowPlugin* plugin = DESKTOP_MULTI_WINDOW_PLUGIN(user_data);
  desktop_multi_window_plugin_handle_method_call(plugin, method_call);
}

void desktop_multi_window_plugin_register_with_registrar_internal(
    FlPluginRegistrar* registrar,
    FlutterWindow* window) {
  DesktopMultiWindowPlugin* plugin = DESKTOP_MULTI_WINDOW_PLUGIN(
      g_object_new(desktop_multi_window_plugin_get_type(), nullptr));
  plugin->window = window;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "mixin.one/desktop_multi_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  // Set channel to window for event notifications
  window->SetChannel(channel);

  // Register WindowChannel plugin for each engine
  window_channel_plugin_register_with_registrar(registrar);

  g_object_unref(plugin);
}

void desktop_multi_window_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto view = fl_plugin_registrar_get_view(registrar);
  auto window = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (GTK_IS_WINDOW(window)) {
    MultiWindowManager::Instance()->AttachMainWindow(window, registrar);
  } else { // variant
    g_critical("can not find GtkWindow instance for main window.");
  }
}

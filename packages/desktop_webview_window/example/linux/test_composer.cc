#include "test_composer.h"

#include <desktop_webview_window/webview_window_composer.h>
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <cstring>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace {

std::map<int64_t, std::string> handled;
// "<browser>:<callback>" in delivery order.
std::vector<std::string> events;

void Record(int64_t browser, const char* event) {
  events.push_back(std::to_string(browser) + ":" + event);
}

GtkWidget* ControlButton(const char* icon, int64_t browser,
                         int32_t (*action)(int64_t)) {
  GtkWidget* button = gtk_button_new_from_icon_name(icon, GTK_ICON_SIZE_BUTTON);
  gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
  g_object_set_data(G_OBJECT(button), "browser",
                    GINT_TO_POINTER(static_cast<gint>(browser)));
  g_signal_connect(button, "clicked",
                   G_CALLBACK(+[](GtkButton* button, gpointer action) {
                     const int64_t browser = GPOINTER_TO_INT(
                         g_object_get_data(G_OBJECT(button), "browser"));
                     reinterpret_cast<int32_t (*)(int64_t)>(action)(browser);
                   }),
                   reinterpret_cast<gpointer>(action));
  return button;
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  Record(request->browser, "compose");
  const std::string mode = request->arguments ? request->arguments : "";
  if (mode.empty()) return DWW_COMPOSE_DEFAULT;
  handled[request->browser] = mode;
  if (mode == "close:compose") {
    Record(request->browser,
           dww_browser_close(request->browser) ? "close-accepted"
                                               : "close-ignored");
    return DWW_COMPOSE_HANDLED;
  }
  if (mode == "sidebar") {
    GtkWidget* column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_size_request(column, 48, -1);
    gtk_box_pack_start(GTK_BOX(column),
                       ControlButton("go-previous-symbolic", request->browser,
                                     dww_browser_go_back),
                       FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(column),
                       ControlButton("go-next-symbolic", request->browser,
                                     dww_browser_go_forward),
                       FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(column),
                       ControlButton("view-refresh-symbolic", request->browser,
                                     dww_browser_reload),
                       FALSE, FALSE, 0);
    GtkWidget* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_box_pack_start(GTK_BOX(row), column, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(row),
                       gtk_separator_new(GTK_ORIENTATION_VERTICAL), FALSE,
                       FALSE, 0);
    gtk_box_pack_start(GTK_BOX(row), GTK_WIDGET(request->webview_view), TRUE,
                       TRUE, 0);
    gtk_container_add(GTK_CONTAINER(request->window), row);
    gtk_widget_show_all(row);
  }
  // Other modes leave webview_view unplaced; it then fills the window.
  return DWW_COMPOSE_HANDLED;
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  Record(state->browser, "navigation");
  const auto found = handled.find(state->browser);
  if (found == handled.end()) return;
  // Close once a page has finished loading.
  if (found->second == "close:navigation" && state->url != nullptr &&
      !state->is_loading) {
    Record(state->browser, dww_browser_close(state->browser)
                               ? "close-accepted"
                               : "close-ignored");
  }
}

void Closing(void*, int64_t browser) {
  Record(browser, "closing");
  const auto found = handled.find(browser);
  if (found != handled.end() && found->second == "close:closing") {
    Record(browser,
           dww_browser_close(browser) ? "close-accepted" : "close-ignored");
  }
  handled.erase(browser);
}

void Collect(GtkWidget* widget, const char* type, std::vector<GtkWidget*>* out) {
  if (strcmp(G_OBJECT_TYPE_NAME(widget), type) == 0 ||
      (strcmp(type, "GtkButton") == 0 && GTK_IS_BUTTON(widget) &&
       // Window controls of a header bar.
       !gtk_style_context_has_class(gtk_widget_get_style_context(widget),
                                    "titlebutton"))) {
    out->push_back(widget);
  }
  if (GTK_IS_CONTAINER(widget)) {
    using Args = std::pair<const char*, std::vector<GtkWidget*>*>;
    Args args(type, out);
    gtk_container_forall(
        GTK_CONTAINER(widget),
        [](GtkWidget* child, gpointer data) {
          auto* args = static_cast<Args*>(data);
          Collect(child, args->first, args->second);
        },
        &args);
  }
}

std::vector<GtkWidget*> Find(GtkWidget* root, const char* type) {
  std::vector<GtkWidget*> found;
  Collect(root, type, &found);
  return found;
}

GtkWidget* WindowArgument(FlValue* args) {
  FlValue* handle = fl_value_lookup_string(args, "handle");
  return handle ? reinterpret_cast<GtkWidget*>(fl_value_get_int(handle))
                : nullptr;
}

FlMethodResponse* Handle(FlMethodCall* call) {
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(method, "composerEvents") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const auto& event : events) {
      fl_value_append_take(list, fl_value_new_string(event.c_str()));
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  }
  if (strcmp(method, "clearComposerEvents") == 0) {
    events.clear();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "gtkTheme") == 0) {
    GtkSettings* settings = gtk_settings_get_default();
    gchar* name = nullptr;
    gboolean dark = FALSE;
    g_object_get(settings, "gtk-theme-name", &name,
                 "gtk-application-prefer-dark-theme", &dark, nullptr);
    g_autoptr(FlValue) previous = fl_value_new_map();
    fl_value_set_string_take(previous, "name", fl_value_new_string(name ? name : ""));
    fl_value_set_string_take(previous, "dark", fl_value_new_bool(dark));
    g_free(name);
    FlValue* new_name = fl_value_lookup_string(args, "name");
    FlValue* new_dark = fl_value_lookup_string(args, "dark");
    if (new_name && new_dark) {
      g_object_set(settings, "gtk-theme-name", fl_value_get_string(new_name),
                   "gtk-application-prefer-dark-theme", fl_value_get_bool(new_dark), nullptr);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(previous));
  }
  if (strcmp(method, "setAppTheme") == 0) {
    GtkSettings* settings = gtk_settings_get_default();
    const auto brightness = fl_value_get_int(fl_value_lookup_string(args, "brightness"));
    // Drop application overrides so System resumes following the desktop.
    gtk_settings_reset_property(settings, "gtk-theme-name");
    gtk_settings_reset_property(settings, "gtk-application-prefer-dark-theme");
    if (brightness >= 0) {
      g_autofree gchar* theme = nullptr;
      g_object_get(settings, "gtk-theme-name", &theme, nullptr);
      // Some desktops select the dark variant by name instead of preference.
      if (theme && g_str_has_suffix(theme, "-dark")) {
        theme[strlen(theme) - strlen("-dark")] = '\0';
        g_object_set(settings, "gtk-theme-name", theme, nullptr);
      }
      g_object_set(settings, "gtk-application-prefer-dark-theme", brightness == 0, nullptr);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  GtkWidget* window = WindowArgument(args);
  if (window == nullptr || !GTK_IS_WINDOW(window)) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("no_window", "Unknown window", nullptr));
  }
  if (strcmp(method, "nativeClose") == 0) {
    gtk_window_close(GTK_WINDOW(window));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "geometry") == 0) {
    GtkWidget* content = gtk_bin_get_child(GTK_BIN(window));
    const auto webviews = Find(window, "WebKitWebView");
    if (content == nullptr || webviews.empty()) {
      return FL_METHOD_RESPONSE(
          fl_method_error_response_new("no_webview", "No WebView", nullptr));
    }
    GtkAllocation content_box;
    GtkAllocation web_box;
    gtk_widget_get_allocation(content, &content_box);
    gtk_widget_get_allocation(webviews.front(), &web_box);
    gint x = 0;
    gint y = 0;
    gtk_widget_translate_coordinates(webviews.front(), content, 0, 0, &x, &y);
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "contentWidth",
                             fl_value_new_int(content_box.width));
    fl_value_set_string_take(result, "contentHeight",
                             fl_value_new_int(content_box.height));
    fl_value_set_string_take(result, "webX", fl_value_new_int(x));
    fl_value_set_string_take(result, "webY", fl_value_new_int(y));
    fl_value_set_string_take(result, "webWidth",
                             fl_value_new_int(web_box.width));
    fl_value_set_string_take(result, "webHeight",
                             fl_value_new_int(web_box.height));
    fl_value_set_string_take(
        result, "buttons",
        fl_value_new_int(static_cast<int64_t>(Find(window, "GtkButton").size())));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  if (strcmp(method, "resize") == 0) {
    gtk_window_resize(
        GTK_WINDOW(window),
        static_cast<gint>(fl_value_get_int(fl_value_lookup_string(args, "width"))),
        static_cast<gint>(fl_value_get_int(fl_value_lookup_string(args, "height"))));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "windowTitle") == 0) {
    const char* title = gtk_window_get_title(GTK_WINDOW(window));
    return FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string(title ? title : "")));
  }
  if (strcmp(method, "clickButton") == 0) {
    const auto buttons = Find(window, "GtkButton");
    const auto index = fl_value_get_int(fl_value_lookup_string(args, "index"));
    if (index < 0 || static_cast<size_t>(index) >= buttons.size()) {
      return FL_METHOD_RESPONSE(
          fl_method_error_response_new("no_button", "No such button", nullptr));
    }
    gtk_button_clicked(GTK_BUTTON(buttons[index]));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

}  // namespace

// Read rendered pixels, rather than get_background_color(), which returns
// white for both an unset override and an explicit white override.
static void RespondPixel(FlMethodCall* call, cairo_surface_t* surface) {
  if (!surface || cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) {
    fl_method_call_respond_error(call, "no_snapshot", "No rendered image", nullptr, nullptr);
    return;
  }
  cairo_surface_flush(surface);
  const int x = cairo_image_surface_get_width(surface) / 2;
  const int y = cairo_image_surface_get_height(surface) / 2;
  const auto* row = reinterpret_cast<const uint32_t*>(
      cairo_image_surface_get_data(surface) + y * cairo_image_surface_get_stride(surface));
  const uint32_t pixel = row[x];
  g_autoptr(FlValue) values = fl_value_new_list();
  for (int shift : {16, 8, 0}) {
    fl_value_append_take(values, fl_value_new_float(((pixel >> shift) & 255) / 255.0));
  }
  const double alpha = cairo_image_surface_get_format(surface) == CAIRO_FORMAT_RGB24
      ? 1.0 : ((pixel >> 24) & 255) / 255.0;
  fl_value_append_take(values, fl_value_new_float(alpha));
  fl_method_call_respond_success(call, values, nullptr);
}

void test_composer_install() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged,
                                    nullptr, Closing};
  dww_set_composer(&composer);
}

void test_composer_register_channel(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Kept alive by the messenger for the engine's lifetime.
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "webview_example/native_test", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer) {
        const char* method = fl_method_call_get_name(call);
        if (strcmp(method, "webviewPixel") == 0 || strcmp(method, "startupPixel") == 0) {
          GtkWidget* window = WindowArgument(fl_method_call_get_args(call));
          const auto views = window ? Find(window, "WebKitWebView") : std::vector<GtkWidget*>();
          if (views.empty()) {
            fl_method_call_respond_error(call, "no_webview", "No WebView", nullptr, nullptr);
            return;
          }
          if (strcmp(method, "startupPixel") == 0) {
            GtkWidget* container = gtk_widget_get_parent(views.front());
            cairo_surface_t* image = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
                gtk_widget_get_allocated_width(container), gtk_widget_get_allocated_height(container));
            cairo_t* cr = cairo_create(image);
            gtk_widget_draw(container, cr);
            cairo_destroy(cr);
            RespondPixel(call, image);
            cairo_surface_destroy(image);
            return;
          }
          webkit_web_view_get_snapshot(WEBKIT_WEB_VIEW(views.front()),
              WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr,
              +[](GObject* source, GAsyncResult* result, gpointer data) {
                g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
                GError* error = nullptr;
                cairo_surface_t* image = webkit_web_view_get_snapshot_finish(
                    WEBKIT_WEB_VIEW(source), result, &error);
                RespondPixel(call, image);
                if (image) cairo_surface_destroy(image);
                g_clear_error(&error);
              }, g_object_ref(call));
          return;
        }
        g_autoptr(FlMethodResponse) response = Handle(call);
        fl_method_call_respond(call, response, nullptr);
      },
      nullptr, nullptr);
}

#include "test_composer.h"

#include <desktop_webview_window/webview_window_composer.h>
#include <gtk/gtk.h>

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
      (strcmp(type, "GtkButton") == 0 && GTK_IS_BUTTON(widget))) {
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
  GtkWidget* window = WindowArgument(args);
  if (window == nullptr || !GTK_IS_WINDOW(window)) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("no_window", "Unknown window", nullptr));
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
        g_autoptr(FlMethodResponse) response = Handle(call);
        fl_method_call_respond(call, response, nullptr);
      },
      nullptr, nullptr);
}

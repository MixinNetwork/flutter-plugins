//
// Created by boyan on 10/21/21.
//

#include "webview_window.h"

#include <utility>
#include <webkit2/webkit2.h>

namespace {

gboolean on_load_failed_with_tls_errors(
    WebKitWebView *web_view,
    char *failing_uri,
    GTlsCertificate *certificate,
    GTlsCertificateFlags errors,
    gpointer user_data) {
  auto *webview = static_cast<WebviewWindow *>(user_data);
  auto *uri = soup_uri_new(failing_uri);
  g_critical("on_load_failed_with_tls_errors: %s %p error= %d", uri->host, webview, errors);
  // TODO allow certificate for some certificate ?
  // maybe we can use the pem from https://source.chromium.org/chromium/chromium/src/+/master:net/data/ssl/ev_roots/
//  webkit_web_context_allow_tls_certificate_for_host(webkit_web_view_get_context(web_view), certificate, uri->host);
//  webkit_web_view_load_uri(web_view, failing_uri);
  return false;
}

GtkWidget *on_create(WebKitWebView *web_view,
                     WebKitNavigationAction *navigation_action,
                     gpointer user_data) {
  return GTK_WIDGET(web_view);
}

}

WebviewWindow::WebviewWindow(
    FlMethodChannel *method_channel,
    int64_t window_id,
    std::function<void()> on_close_callback,
    const std::string &title,
    int width,
    int height
) : method_channel_(method_channel),
    window_id_(window_id),
    on_close_callback_(std::move(on_close_callback)),
    default_user_agent_() {
  g_object_ref(method_channel_);

  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_signal_connect(G_OBJECT(window_), "destroy",
                   G_CALLBACK(+[](GtkWidget *, gpointer arg) {
                     auto *window = static_cast<WebviewWindow *>(arg);
                     if (window->on_close_callback_) {
                       window->on_close_callback_();
                     }
                     auto *args = fl_value_new_map();
                     fl_value_set(args, fl_value_new_string("id"), fl_value_new_int(window->window_id_));
                     fl_method_channel_invoke_method(
                         FL_METHOD_CHANNEL(window->method_channel_), "onWindowClose", args,
                         nullptr, nullptr, nullptr);
                   }), this);
  gtk_window_set_title(GTK_WINDOW(window_), title.c_str());
  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);

  webview_ = webkit_web_view_new();
  g_signal_connect(G_OBJECT(webview_), "load-failed-with-tls-errors",
                   G_CALLBACK(on_load_failed_with_tls_errors), this);
  g_signal_connect(G_OBJECT(webview_), "create",
                   G_CALLBACK(on_create), this);
  auto settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_javascript_can_open_windows_automatically(settings, true);
  default_user_agent_ = webkit_settings_get_user_agent(settings);

  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(webview_));
  gtk_widget_grab_focus(GTK_WIDGET(webview_));

  gtk_widget_show_all(window_);

}

WebviewWindow::~WebviewWindow() {
  g_object_unref(method_channel_);
  g_debug("~WebviewWindow");
}

void WebviewWindow::Navigate(const char *url) {
  webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview_), url);
}

void WebviewWindow::RunJavaScript(const char *java_script) {
  auto *manager = webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));
  webkit_user_content_manager_add_script(
      manager,
      webkit_user_script_new(java_script,
                             WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                             WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
                             nullptr,
                             nullptr));
}

void WebviewWindow::SetApplicationNameForUserAgent(const std::string &app_name) {
  auto *setting = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_user_agent(setting, (default_user_agent_ + app_name).c_str());
}

void WebviewWindow::Close() {
  gtk_window_close(GTK_WINDOW(window_));
}

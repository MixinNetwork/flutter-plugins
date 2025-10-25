#include "flutter_window.h"

#include <iostream>

FlutterWindow::FlutterWindow(const std::string& id,
                             const std::string& argument,
                             GtkWidget* window)
    : id_(id), window_argument_(argument), window_(window) {}

FlutterWindow::~FlutterWindow() = default;

void FlutterWindow::SetChannel(FlMethodChannel* channel) {
  channel_ = channel;
}

void FlutterWindow::NotifyWindowEvent(const gchar* event, FlValue* data) {
  if (channel_) {
    fl_method_channel_invoke_method(channel_, event, data, nullptr, nullptr, nullptr);
  }
}

void FlutterWindow::Show() {
  if (window_) {
    gtk_widget_show(GTK_WIDGET(window_));
  }
}

void FlutterWindow::Hide() {
  if (window_) {
    gtk_widget_hide(GTK_WIDGET(window_));
  }
}

void FlutterWindow::HandleWindowMethod(const gchar* method,
                                       FlValue* arguments,
                                       FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "window_show") == 0) {
    Show();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "window_hide") == 0) {
    Hide();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    g_autofree gchar* error_msg = g_strdup_printf("unknown method: %s", method);
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("-1", error_msg, nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
}

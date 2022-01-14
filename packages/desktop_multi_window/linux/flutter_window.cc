//
// Created by yangbin on 2022/1/11.
//

#include "flutter_window.h"

#include <iostream>

#include "include/desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

WindowCreatedCallback _g_window_created_callback = nullptr;

}

FlutterWindow::FlutterWindow(
    int64_t id,
    const std::string &args,
    const std::shared_ptr<FlutterWindowCallback> &callback
) : callback_(callback), id_(id), dragging_(FALSE) {
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(window_), 1280, 720);
  gtk_window_set_title(GTK_WINDOW(window_), "");
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);
  gtk_widget_show(GTK_WIDGET(window_));

  g_signal_connect(window_, "destroy", G_CALLBACK(+[](GtkWidget *, gpointer arg) {
    auto *self = static_cast<FlutterWindow *>(arg);
    if (auto callback = self->callback_.lock()) {
      callback->OnWindowClose(self->id_);
      callback->OnWindowDestroy(self->id_);
    }
  }), this);

  g_signal_connect(window_, "event-after", G_CALLBACK(+[](GtkWidget *, GdkEvent *event, gpointer arg) {
    auto *self = static_cast<FlutterWindow *>(arg);

    if (event->type == GDK_ENTER_NOTIFY) {
      if (self->dragging_) {
        self->dragging_ = false;

//        auto newEvent = (GdkEventButton *)gdk_event_new(GDK_BUTTON_RELEASE);
//        newEvent->x = 0;
//        newEvent->y = 0;
//        newEvent->button = 1;
//        newEvent->type = GDK_BUTTON_RELEASE;
//        newEvent->time = g_get_monotonic_time();
//        gboolean result;
//        g_signal_emit_by_name(self->event_box, "button-release-event",
//                              newEvent, &result);
//        gdk_event_free((GdkEvent *)newEvent);

      }
    }
    return FALSE;
  }), this);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char *entrypoint_args[] = {"multi_window", g_strdup_printf("%ld", id_), args.c_str(), nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project, const_cast<char **>(entrypoint_args));

  fl_view_ = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(fl_view_));
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(fl_view_));

  if (_g_window_created_callback) {
    _g_window_created_callback(FL_PLUGIN_REGISTRY(fl_view_));
  }
  g_autoptr(FlPluginRegistrar) desktop_multi_window_registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(fl_view_), "DesktopMultiWindowPlugin");
  desktop_multi_window_plugin_register_with_registrar(desktop_multi_window_registrar);

  gtk_widget_grab_focus(GTK_WIDGET(fl_view_));
  gtk_widget_hide(GTK_WIDGET(window_));
}

void FlutterWindow::Show() {
  gtk_widget_show(window_);
  gtk_widget_show(GTK_WIDGET(fl_view_));
}

void FlutterWindow::Hide() {
  gtk_widget_hide(window_);
}

void FlutterWindow::SetBounds(double_t x, double_t y, double_t width, double_t height) {
  gtk_window_move(GTK_WINDOW(window_), static_cast<gint>(x), static_cast<gint>(y));
  gtk_window_resize(GTK_WINDOW(window_), static_cast<gint>(width), static_cast<gint>(height));
}

void FlutterWindow::SetTitle(const std::string &title) {
  gtk_window_set_title(GTK_WINDOW(window_), title.c_str());
}

void FlutterWindow::SetMaxSize(int64_t width, int64_t height) {
  // TODO: implement this.
}

void FlutterWindow::SetMinSize(int64_t width, int64_t height) {
  // TODO: implement this.
}

void FlutterWindow::Center() {
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);
}

void FlutterWindow::Close() {
  gtk_window_close(GTK_WINDOW(window_));
}

void FlutterWindow::StartDragging() {
  auto screen = gtk_window_get_screen(GTK_WINDOW(window_));
  auto display = gdk_screen_get_display(screen);
  auto seat = gdk_display_get_default_seat(display);
  auto device = gdk_seat_get_pointer(seat);

  gint root_x, root_y;
  gdk_device_get_position(device, nullptr, &root_x, &root_y);
  auto timestamp = (guint32) g_get_monotonic_time();

  dragging_ = TRUE;
  gtk_window_begin_move_drag(GTK_WINDOW(window_), 1, root_x, root_y, timestamp);
}

FlutterWindow::~FlutterWindow() = default;

void desktop_multi_window_plugin_set_window_created_callback(WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}
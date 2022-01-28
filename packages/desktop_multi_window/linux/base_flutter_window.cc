//
// Created by boyan on 2022/1/27.
//

#include "base_flutter_window.h"

void BaseFlutterWindow::Show() {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_widget_show(GTK_WIDGET(window));
}

void BaseFlutterWindow::Hide() {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_widget_hide(GTK_WIDGET(window));
}

void BaseFlutterWindow::SetBounds(double_t x, double_t y, double_t width, double_t height) {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_window_move(GTK_WINDOW(window), static_cast<gint>(x), static_cast<gint>(y));
  gtk_window_resize(GTK_WINDOW(window), static_cast<gint>(width), static_cast<gint>(height));
}

void BaseFlutterWindow::SetTitle(const std::string &title) {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_window_set_title(GTK_WINDOW(window), title.c_str());
}

void BaseFlutterWindow::Center() {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
}

void BaseFlutterWindow::Close() {
  auto window = GetWindow();
  if (!window) {
    return;
  }
  gtk_window_close(GTK_WINDOW(window));
}
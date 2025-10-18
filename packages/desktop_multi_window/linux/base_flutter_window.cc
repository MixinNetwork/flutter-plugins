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
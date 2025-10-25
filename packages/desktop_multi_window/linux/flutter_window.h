#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <cmath>
#include <cstdint>
#include <memory>
#include <string>

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

class FlutterWindow {
 public:
  FlutterWindow(const std::string& id,
                const std::string& argument,
                GtkWidget* window);
  ~FlutterWindow();

  std::string GetWindowId() const { return id_; }

  std::string GetWindowArgument() const { return window_argument_; }

  GtkWindow* GetWindow() { return GTK_WINDOW(window_); }

  void SetChannel(FlMethodChannel* channel);

  void NotifyWindowEvent(const gchar* event, FlValue* data);

  void Show();

  void Hide();

  void HandleWindowMethod(const gchar* method,
                          FlValue* arguments,
                          FlMethodCall* method_call);

 private:
  std::string id_;
  std::string window_argument_;
  GtkWidget* window_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

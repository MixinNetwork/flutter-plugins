#ifndef DESKTOP_MULTI_WINDOW_LINUX_BASE_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_LINUX_BASE_FLUTTER_WINDOW_H_

#include <string>
#include <cmath>
#include <gtk/gtk.h>
#include <flutter_linux/flutter_linux.h>

class BaseFlutterWindow {
 public:

  virtual ~BaseFlutterWindow() = default;

  virtual std::string GetWindowId() const = 0;

  virtual std::string GetWindowArgument() const = 0;

  virtual void HandleWindowMethod(
      const gchar* method,
      FlValue* arguments,
      FlMethodCall* method_call) = 0;

  void Show();

  void Hide();

 protected:

  virtual GtkWindow* GetWindow() = 0;
};

#endif //DESKTOP_MULTI_WINDOW_LINUX_BASE_FLUTTER_WINDOW_H_

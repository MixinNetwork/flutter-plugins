#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <cstdint>
#include <memory>
#include <cmath>
#include <string>

#include <gtk/gtk.h>
#include <flutter_linux/flutter_linux.h>

#include "base_flutter_window.h"

class FlutterWindowCallback {

 public:
  virtual void OnWindowClose(const std::string& id) = 0;

  virtual void OnWindowDestroy(const std::string& id) = 0;

};

class FlutterWindow : public BaseFlutterWindow {

 public:

  FlutterWindow(const std::string& id, const std::string &args, const std::shared_ptr<FlutterWindowCallback> &callback);
  ~FlutterWindow() override;

  std::string GetWindowId() const override {
    return id_;
  }

  std::string GetWindowArgument() const override {
    return window_argument_;
  }

  void HandleWindowMethod(
      const gchar* method,
      FlValue* arguments,
      FlMethodCall* method_call) override;

 protected:

  GtkWindow *GetWindow() override {
    return GTK_WINDOW(window_);
  }

 private:

  std::weak_ptr<FlutterWindowCallback> callback_;

  std::string id_;
  std::string window_argument_;

  GtkWidget *window_ = nullptr;

};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

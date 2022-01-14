//
// Created by yangbin on 2022/1/11.
//

#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <cstdint>
#include <memory>
#include <cmath>

#include <gtk/gtk.h>
#include <flutter_linux/flutter_linux.h>

class FlutterWindowCallback {

 public:
  virtual void OnWindowClose(int64_t id) = 0;

  virtual void OnWindowDestroy(int64_t id) = 0;

};

class FlutterWindow {

 public:

  FlutterWindow(int64_t id, const std::string& args, const std::shared_ptr<FlutterWindowCallback> &callback);
  ~FlutterWindow();

  void Show();

  void Hide();

  void Close();

  void SetTitle(const std::string &title);

  void SetBounds(double_t x, double_t y, double_t width, double_t height);

  void SetMinSize(int64_t width, int64_t height);

  void SetMaxSize(int64_t width, int64_t height);

  void Center();

  void StartDragging();

 private:

  std::weak_ptr<FlutterWindowCallback> callback_;

  int64_t id_;

  gboolean dragging_;

  GtkWidget *window_ = nullptr;
  FlView *fl_view_ = nullptr;
};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

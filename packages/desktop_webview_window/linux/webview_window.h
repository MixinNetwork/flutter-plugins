//
// Created by boyan on 10/21/21.
//

#ifndef WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_
#define WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include "functional"

#include <string>

class WebviewWindow {
 public:
  WebviewWindow(
      FlMethodChannel *method_channel,
      int64_t window_id,
      std::function<void()> on_close_callback,
      const std::string& title, int width, int height
  );

  virtual ~WebviewWindow();

  void Navigate(const char* url);

  void RunJavaScript(const char* java_script);

  void Close();

 private:
  FlMethodChannel *method_channel_;
  int64_t window_id_;
  std::function<void()> on_close_callback_;

  GtkWidget *window_ = nullptr;
  GtkWidget *webview_ = nullptr;

};

#endif //WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_

//
// Created by boyan on 10/21/21.
//

#ifndef WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_
#define WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

#include <functional>
#include <string>
#include <unordered_map>

#include "title_bar_engine.h"

typedef struct {
    GMainLoop *loop;
    GList *cookies;
} CookieData;

void get_cookies_callback(WebKitCookieManager *manager, GAsyncResult *res,
                          gpointer user_data);

GList *get_cookies_sync(WebKitWebView *web_view);

class WebviewWindow {
 public:
  WebviewWindow(FlMethodChannel *method_channel, int64_t window_id,
                std::function<void()> on_close_callback,
                const std::string &title, int width, int height,
                int title_bar_height, int title_bar_top_padding,
                TitleBarEngine *title_bar_engine, GtkWindow *parent);

  virtual ~WebviewWindow();

  void Navigate(const char *url);

  void RunJavaScriptWhenContentReady(const char *java_script);

  void Close();

  void SetApplicationNameForUserAgent(const std::string &app_name);

  void OnLoadChanged(WebKitLoadEvent load_event);

  void GoBack();

  void GoForward();

  void Reload();

  void StopLoading();

  FlValue* GetAllCookies();

  gboolean DecidePolicy(WebKitPolicyDecision *decision,
                        WebKitPolicyDecisionType type);

  void EvaluateJavaScript(const char *java_script, FlMethodCall *call);

  void RegisterJavaScriptChannel(const std::string &name);

  void UnregisterJavaScriptChannel(const std::string &name);

 private:
  void OnDestroyed();
  void DisconnectCallbacks();

  FlMethodChannel *method_channel_;
  int64_t window_id_;
  std::function<void()> on_close_callback_;

  std::string default_user_agent_;

  GtkWidget *window_ = nullptr;
  GtkWidget *webview_ = nullptr;
  GtkBox *box_ = nullptr;
  WebKitUserContentManager *content_manager_ = nullptr;
  GCancellable *javascript_cancellable_ = nullptr;
  TitleBarEngine *title_bar_engine_ = nullptr;  // Owned by the plugin.
  int64_t title_bar_view_id_ = -1;
  bool closing_ = false;
  bool closed_ = false;

  std::unordered_map<std::string, gulong> js_channel_handler_ids_;
};

#endif  // WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_

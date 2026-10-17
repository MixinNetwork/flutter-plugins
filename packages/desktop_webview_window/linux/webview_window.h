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

#include "composer_runtime.h"

class WebviewWindow : public dww::Browser {
 public:
  // Posts a browser event to Dart; |args| is a map that gains the "id".
  using EventSink = std::function<void(const char *method, FlValue *args)>;
  // Asks Dart to decide a top-level navigation. |decision| is referenced and
  // must be used or ignored once Dart replies.
  using NavigationRequest =
      std::function<void(const char *url, WebKitPolicyDecision *decision)>;

  struct Options {
    std::string title;
    int width = 1280;
    int height = 720;
    int x = 0;
    int y = 0;
    bool use_position = false;
    bool open_maximized = false;
    bool open_hidden = false;
    uint32_t title_bar = 0xF;
    bool has_composer_arguments = false;
    std::string composer_arguments;
    std::string javascript_bridge;
  };

  WebviewWindow(EventSink emit, NavigationRequest request_navigation,
                int64_t window_id, std::function<void()> on_close_callback,
                const Options &options);

  ~WebviewWindow() override;

  // Composes, publishes the initial navigation state and shows the window.
  // A close requested meanwhile skips the rest; finish it with DestroyNow().
  void Start(const Options &options);

  // Destroys the window now. Only valid outside composer callbacks.
  void DestroyNow();

  [[nodiscard]] bool IsClosing() const { return closing_; }

  // With |decide| false, this navigation bypasses the Dart decision.
  void Navigate(const char *url, bool decide);

  [[nodiscard]] GtkWidget *NativeWindow() const { return window_; }

  void SetUrlRequestEnabled(bool enabled) { url_request_enabled_ = enabled; }

  void RunJavaScriptWhenContentReady(const char *java_script);

  void SetApplicationNameForUserAgent(const std::string &app_name);

  bool GoBack() override;

  bool GoForward() override;

  bool Reload() override;

  bool Stop() override;

  // Requests closing. Inside a composer callback it takes effect afterwards.
  bool Close() override;

  void GetAllCookies(FlMethodCall *call);

  gboolean DecidePolicy(WebKitPolicyDecision *decision,
                        WebKitPolicyDecisionType type);

  // Replies with the result serialized as JSON, or null.
  void EvaluateJavaScript(const char *java_script, FlMethodCall *call);

  void OpenInspector();

 private:
  void OnDestroyed();
  void DisconnectCallbacks();
  void Emit(const char *method, FlValue *args = nullptr);
  void OnBridgeMessage(WebKitJavascriptResult *result);
  void PublishNavigationState();
  void DeliverClosing();

  EventSink emit_;
  NavigationRequest request_navigation_;
  int64_t window_id_;
  std::function<void()> on_close_callback_;

  std::string default_user_agent_;

  GtkWidget *window_ = nullptr;
  // Holds the WebView; handed to the composer as webview_view.
  GtkWidget *container_ = nullptr;
  GtkWidget *webview_ = nullptr;
  WebKitUserContentManager *content_manager_ = nullptr;
  GCancellable *javascript_cancellable_ = nullptr;
  dww::ComposerBinding composer_;
  bool closing_ = false;
  bool closed_ = false;
  guint close_source_ = 0;
  bool url_request_enabled_ = false;
  // Set by Navigate(decide: false): the next decision skips Dart.
  bool skip_next_decision_ = false;
  gulong bridge_handler_id_ = 0;

  struct NavigationState {
    bool can_go_back = false;
    bool can_go_forward = false;
    bool is_loading = false;
    std::string url;
    std::string title;
    bool operator==(const NavigationState &other) const {
      return can_go_back == other.can_go_back &&
             can_go_forward == other.can_go_forward &&
             is_loading == other.is_loading && url == other.url &&
             title == other.title;
    }
  };
  NavigationState navigation_;
  bool published_ = false;
};

#endif  // WEBVIEW_WINDOW_LINUX_WEBVIEW_WINDOW_H_

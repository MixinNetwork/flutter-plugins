//
// Created by boyan on 10/21/21.
//

#include "webview_window.h"
#include <memory>
#include <string>
#include <utility>

#if WEBKIT_MAJOR_VERSION < 2 || \
    (WEBKIT_MAJOR_VERSION == 2 && WEBKIT_MINOR_VERSION < 40)
#define WEBKIT_OLD_USED
#endif

namespace {

gboolean on_load_failed_with_tls_errors(WebKitWebView *web_view,
                                        char *failing_uri,
                                        GTlsCertificate *certificate,
                                        GTlsCertificateFlags errors,
                                        gpointer user_data) {
  auto *webview = static_cast<WebviewWindow *>(user_data);
  g_critical("on_load_failed_with_tls_errors: %s %p error= %d", failing_uri,
             webview, errors);
  // TODO allow certificate for some certificate ?
  // maybe we can use the pem from
  // https://source.chromium.org/chromium/chromium/src/+/master:net/data/ssl/ev_roots/
  //  webkit_web_context_allow_tls_certificate_for_host(webkit_web_view_get_context(web_view),
  //  certificate, uri->host); webkit_web_view_load_uri(web_view, failing_uri);
  return false;
}

GtkWidget *on_create(WebKitWebView *web_view,
                     WebKitNavigationAction *navigation_action,
                     gpointer user_data) {
  // WebKit expects either a new view related to web_view or nullptr here.
  // Handing back web_view itself aborts in WebCore on some builds, so load
  // new windows in the same view, as on macOS and Windows. The load goes
  // through the navigation decision.
  webkit_web_view_load_request(
      web_view, webkit_navigation_action_get_request(navigation_action));
  return nullptr;
}

// The JavaScript bridge's single script message handler.
constexpr char kBridgeHandler[] = "desktopWebview";
constexpr char kStartupHandler[] = "desktopWebviewStartup";
constexpr char kStartupWorld[] = "desktopWebviewStartup";

// Asks where to save a download, as on macOS and Windows. Runs before any
// data is written; cancelling the chooser cancels the download.
gboolean on_decide_destination(WebKitDownload *download,
                               const gchar *suggested_filename,
                               gpointer) {
  auto *web_view = webkit_download_get_web_view(download);
  GtkWidget *toplevel =
      web_view ? gtk_widget_get_toplevel(GTK_WIDGET(web_view)) : nullptr;
  GtkFileChooserNative *chooser = gtk_file_chooser_native_new(
      nullptr, GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : nullptr,
      GTK_FILE_CHOOSER_ACTION_SAVE, nullptr, nullptr);
  gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(chooser),
                                                 TRUE);
  const gchar *downloads =
      g_get_user_special_dir(G_USER_DIRECTORY_DOWNLOAD);
  if (downloads != nullptr) {
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(chooser), downloads);
  }
  if (suggested_filename != nullptr) {
    gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(chooser),
                                      suggested_filename);
  }
  if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(chooser)) ==
      GTK_RESPONSE_ACCEPT) {
    g_autofree gchar *uri =
        gtk_file_chooser_get_uri(GTK_FILE_CHOOSER(chooser));
    webkit_download_set_allow_overwrite(download, TRUE);
    webkit_download_set_destination(download, uri);
  } else {
    webkit_download_cancel(download);
  }
  g_object_unref(chooser);
  return TRUE;
}

bool is_attachment(WebKitURIResponse *response) {
  SoupMessageHeaders *headers = webkit_uri_response_get_http_headers(response);
  if (headers == nullptr) return false;
  const char *disposition =
      soup_message_headers_get_one(headers, "Content-Disposition");
  return disposition != nullptr &&
         g_ascii_strncasecmp(disposition, "attachment", 10) == 0;
}

gboolean decide_policy_cb(WebKitWebView *web_view,
                          WebKitPolicyDecision *decision,
                          WebKitPolicyDecisionType type, gpointer user_data) {
  auto *window = static_cast<WebviewWindow *>(user_data);
  return window->DecidePolicy(decision, type);
}

}  // namespace

WebviewWindow::WebviewWindow(EventSink emit,
                             NavigationRequest request_navigation,
                             int64_t window_id,
                             std::function<void()> on_close_callback,
                             const Options &options)
    : emit_(std::move(emit)),
      request_navigation_(std::move(request_navigation)),
      window_id_(window_id),
      on_close_callback_(std::move(on_close_callback)),
      default_user_agent_() {
  javascript_cancellable_ = g_cancellable_new();
  // An independent top-level window, as on macOS and Windows: not transient
  // for the app window, so it does not stay above it.
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(window_);
  g_signal_connect(G_OBJECT(window_), "destroy",
                   G_CALLBACK(+[](GtkWidget *, gpointer arg) {
                     auto *window = static_cast<WebviewWindow *>(arg);
                     window->OnDestroyed();
                   }),
                   this);
  // Window-manager close requests take the same path as every other close.
  g_signal_connect(G_OBJECT(window_), "delete-event",
                   G_CALLBACK(+[](GtkWidget *, GdkEvent *, gpointer arg) {
                     static_cast<WebviewWindow *>(arg)->Close();
                     return TRUE;
                   }),
                   this);
  gtk_window_set_title(GTK_WINDOW(window_), options.title.c_str());
  gtk_window_set_default_size(GTK_WINDOW(window_), options.width,
                              options.height);
  if (options.use_position) {
    gtk_window_move(GTK_WINDOW(window_), options.x, options.y);
  } else {
    gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);
  }
  if (options.open_maximized) {
    gtk_window_maximize(GTK_WINDOW(window_));
  }

  webview_ = webkit_web_view_new();
  g_object_ref_sink(webview_);
  g_signal_connect(webview_, "load-changed",
                   G_CALLBACK(+[](WebKitWebView *, WebKitLoadEvent event, gpointer arg) {
                     auto *window = static_cast<WebviewWindow *>(arg);
                     if (event == WEBKIT_LOAD_COMMITTED) window->document_committed_ = true;
                     if (event == WEBKIT_LOAD_FINISHED && window->startup_cover_ &&
                         window->document_committed_) {
                       window->FinishStartupBackground();
                     }
                   }), this);
  content_manager_ = WEBKIT_USER_CONTENT_MANAGER(g_object_ref(
      webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_))));
  // Reveal the first contentful paint even if the server is still streaming
  // HTML. The isolated world keeps page scripts from overriding this signal.
  webkit_user_content_manager_register_script_message_handler_in_world(
      content_manager_, kStartupHandler, kStartupWorld);
  startup_handler_id_ = g_signal_connect(
      content_manager_, "script-message-received::desktopWebviewStartup",
      G_CALLBACK(+[](WebKitUserContentManager *, WebKitJavascriptResult *, gpointer arg) {
        static_cast<WebviewWindow *>(arg)->FinishStartupBackground();
      }), this);
  startup_script_ = webkit_user_script_new_for_world(
      R"JS((() => {
        const reveal = () => requestAnimationFrame(() => requestAnimationFrame(() =>
          window.webkit.messageHandlers.desktopWebviewStartup.postMessage(null)));
        if (typeof PerformanceObserver === 'function' &&
            PerformanceObserver.supportedEntryTypes &&
            PerformanceObserver.supportedEntryTypes.indexOf('paint') !== -1) {
          const observer = new PerformanceObserver(list => {
            if (list.getEntries().some(entry => entry.name === 'first-contentful-paint')) {
              observer.disconnect();
              reveal();
            }
          });
          observer.observe({type: 'paint', buffered: true});
        } else {
          // Older WebKit releases can still reveal before images finish.
          document.addEventListener('DOMContentLoaded', reveal, {once: true});
        }
      })();)JS",
      WEBKIT_USER_CONTENT_INJECT_TOP_FRAME, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
      kStartupWorld, nullptr, nullptr);
  webkit_user_content_manager_add_script(content_manager_, startup_script_);
  g_signal_connect(G_OBJECT(webview_), "load-failed-with-tls-errors",
                   G_CALLBACK(on_load_failed_with_tls_errors), this);
  g_signal_connect(G_OBJECT(webview_), "create", G_CALLBACK(on_create), this);
  g_signal_connect(G_OBJECT(webview_), "decide-policy",
                   G_CALLBACK(decide_policy_cb), this);
  // Downloads are reported by the shared web context; keep this view's own.
  g_signal_connect(
      webkit_web_view_get_context(WEBKIT_WEB_VIEW(webview_)),
      "download-started",
      G_CALLBACK(+[](WebKitWebContext *, WebKitDownload *download,
                     gpointer arg) {
        auto *window = static_cast<WebviewWindow *>(arg);
        if (webkit_download_get_web_view(download) !=
            WEBKIT_WEB_VIEW(window->webview_)) {
          return;
        }
        g_signal_connect(download, "decide-destination",
                         G_CALLBACK(on_decide_destination), nullptr);
      }),
      this);
  for (const char *property : {"notify::uri", "notify::title",
                               "notify::is-loading"}) {
    g_signal_connect(G_OBJECT(webview_), property,
                     G_CALLBACK(+[](GObject *, GParamSpec *, gpointer arg) {
                       static_cast<WebviewWindow *>(arg)
                           ->PublishNavigationState();
                     }),
                     this);
  }
  g_signal_connect(
      webkit_web_view_get_back_forward_list(WEBKIT_WEB_VIEW(webview_)),
      "changed",
      G_CALLBACK(+[](WebKitBackForwardList *, WebKitBackForwardListItem *,
                     gpointer, gpointer arg) {
        static_cast<WebviewWindow *>(arg)->PublishNavigationState();
      }),
      this);

  auto settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_javascript_can_open_windows_automatically(settings, true);
  default_user_agent_ = webkit_settings_get_user_agent(settings);

  if (!options.javascript_bridge.empty()) {
    webkit_user_content_manager_register_script_message_handler(
        content_manager_, kBridgeHandler);
    bridge_handler_id_ = g_signal_connect(
        content_manager_, "script-message-received::desktopWebview",
        G_CALLBACK(+[](WebKitUserContentManager *, WebKitJavascriptResult *result,
                       gpointer user_data) {
          static_cast<WebviewWindow *>(user_data)->OnBridgeMessage(result);
        }),
        this);
    RunJavaScriptWhenContentReady(options.javascript_bridge.c_str());
  }

  // Keep WebKit's background unset so it can follow each document's
  // color-scheme. A GTK cover hides the initial blank frame instead.
  container_ = gtk_overlay_new();
  g_object_ref_sink(container_);
  gtk_container_add(GTK_CONTAINER(container_), webview_);
  startup_cover_ = gtk_drawing_area_new();
  gtk_widget_set_halign(startup_cover_, GTK_ALIGN_FILL);
  gtk_widget_set_valign(startup_cover_, GTK_ALIGN_FILL);
  g_signal_connect(startup_cover_, "draw",
                   G_CALLBACK((+[](GtkWidget *widget, cairo_t *cr, gpointer) -> gboolean {
                     GdkRGBA color{1, 1, 1, 1};
                     gtk_style_context_lookup_color(gtk_widget_get_style_context(widget),
                                                    "theme_base_color", &color);
                     gdk_cairo_set_source_rgba(cr, &color);
                     cairo_paint(cr);
                     return TRUE;
                   })), nullptr);
  gtk_overlay_add_overlay(GTK_OVERLAY(container_), startup_cover_);
  gtk_widget_show_all(container_);
}

void WebviewWindow::Start(const Options &options) {
  dww::RegisterBrowser(window_id_, this);
  const DWWComposeRequest request{
      window_id_, window_, container_,
      options.has_composer_arguments ? options.composer_arguments.c_str()
                                     : nullptr,
      options.title_bar};
  composer_.Compose(request);
  if (closing_) return;
  if (gtk_widget_get_parent(container_) == nullptr) {
    if (gtk_bin_get_child(GTK_BIN(window_)) == nullptr) {
      gtk_container_add(GTK_CONTAINER(window_), container_);
    } else {
      g_warning("desktop_webview_window: the composer filled browser %" G_GINT64_FORMAT
                " without placing its webview_view",
                window_id_);
    }
  }
  PublishNavigationState();
  if (closing_) return;
  if (!options.open_hidden) {
    gtk_widget_show(window_);
  }
  gtk_widget_grab_focus(webview_);
}

void WebviewWindow::Emit(const char *method, FlValue *args) {
  if (closed_ || !emit_) return;
  g_autoptr(FlValue) map = args ? fl_value_ref(args) : fl_value_new_map();
  fl_value_set_string_take(map, "id", fl_value_new_int(window_id_));
  emit_(method, map);
}

void WebviewWindow::OnBridgeMessage(WebKitJavascriptResult *result) {
  if (closing_ || closed_) return;
  JSCValue *value = webkit_javascript_result_get_js_value(result);
  // The injected bridge always posts a JSON string.
  if (!jsc_value_is_string(value)) return;
  g_autofree gchar *message = jsc_value_to_string(value);
  if (message == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "message", fl_value_new_string(message));
  Emit("onJavaScriptMessage", args);
}

void WebviewWindow::OpenInspector() {
  if (closing_ || closed_) return;
  auto *settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_enable_developer_extras(settings, TRUE);
  webkit_web_inspector_show(
      webkit_web_view_get_inspector(WEBKIT_WEB_VIEW(webview_)));
}

WebviewWindow::~WebviewWindow() {
  // The plugin can also dispose a still-open window during engine shutdown.
  // Remove callbacks first so GTK destruction cannot re-enter its owner map.
  on_close_callback_ = nullptr;
  if (close_source_ != 0) {
    g_source_remove(close_source_);
    close_source_ = 0;
  }
  if (!closed_) {
    closing_ = true;
    composer_.BeginClose();
    DeliverClosing();
    dww::UnregisterBrowser(window_id_);
  }
  DisconnectCallbacks();
  if (window_ != nullptr) {
    g_signal_handlers_disconnect_by_data(window_, this);
    gtk_widget_destroy(window_);
    g_clear_object(&window_);
  }
  g_clear_object(&container_);
  g_clear_object(&webview_);
  g_clear_object(&content_manager_);
  g_clear_object(&javascript_cancellable_);
}

void WebviewWindow::DisconnectCallbacks() {
  if (javascript_cancellable_ != nullptr) {
    g_cancellable_cancel(javascript_cancellable_);
  }
  if (webview_ != nullptr) {
    g_signal_handlers_disconnect_by_data(
        webkit_web_view_get_back_forward_list(WEBKIT_WEB_VIEW(webview_)),
        this);
    g_signal_handlers_disconnect_by_data(webview_, this);
    g_signal_handlers_disconnect_by_data(
        webkit_web_view_get_context(WEBKIT_WEB_VIEW(webview_)), this);
  }
  if (content_manager_ != nullptr && bridge_handler_id_ != 0) {
    g_signal_handler_disconnect(content_manager_, bridge_handler_id_);
    webkit_user_content_manager_unregister_script_message_handler(
        content_manager_, kBridgeHandler);
    bridge_handler_id_ = 0;
  }
  if (content_manager_ != nullptr && startup_handler_id_ != 0) {
    g_signal_handler_disconnect(content_manager_, startup_handler_id_);
    webkit_user_content_manager_unregister_script_message_handler_in_world(
        content_manager_, kStartupHandler, kStartupWorld);
    startup_handler_id_ = 0;
  }
  if (startup_script_) {
    webkit_user_content_manager_remove_script(content_manager_, startup_script_);
    webkit_user_script_unref(startup_script_);
    startup_script_ = nullptr;
  }
}

void WebviewWindow::FinishStartupBackground() {
  if (closing_ || closed_ || !startup_cover_) return;
  gtk_widget_destroy(startup_cover_);
  startup_cover_ = nullptr;
  webkit_user_content_manager_remove_script(content_manager_, startup_script_);
  webkit_user_script_unref(startup_script_);
  startup_script_ = nullptr;
}

void WebviewWindow::DeliverClosing() { composer_.Closing(window_id_); }

void WebviewWindow::OnDestroyed() {
  if (closed_) return;
  closing_ = true;
  composer_.BeginClose();
  // Normally delivered by DestroyNow(); this covers an external destroy.
  DeliverClosing();
  closed_ = true;
  dww::UnregisterBrowser(window_id_);
  DisconnectCallbacks();

  if (emit_) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "id", fl_value_new_int(window_id_));
    emit_("onWindowClose", args);
  }

  // This erases the owning unique_ptr. Move the callable off the object and
  // perform ALL member access, notifications and cleanup before invoking it.
  // In particular, do not read window_id_ or emit_ after this call.
  auto on_close = std::move(on_close_callback_);
  if (on_close) on_close();
}

void WebviewWindow::Navigate(const char *url, bool decide) {
  if (closing_ || closed_) return;
  skip_next_decision_ = !decide;
  webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview_), url);
}

void WebviewWindow::RunJavaScriptWhenContentReady(const char *java_script) {
  if (closing_ || closed_) return;
  WebKitUserScript *script = webkit_user_script_new(
      java_script, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(content_manager_, script);
  webkit_user_script_unref(script);
}

void WebviewWindow::SetApplicationNameForUserAgent(
    const std::string &app_name) {
  if (closing_ || closed_) return;
  auto *setting = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_user_agent(setting,
                                 (default_user_agent_ + app_name).c_str());
}

bool WebviewWindow::Close() {
  if (closing_ || closed_ || window_ == nullptr) return false;
  closing_ = true;
  composer_.BeginClose();
  if (composer_.dispatching()) {
    // Composer code is on the stack; tear down once it has returned.
    close_source_ = g_idle_add(
        +[](gpointer arg) -> gboolean {
          auto *window = static_cast<WebviewWindow *>(arg);
          window->close_source_ = 0;
          window->DestroyNow();
          return G_SOURCE_REMOVE;
        },
        this);
    return true;
  }
  // Destroys this object; touch nothing afterwards.
  DestroyNow();
  return true;
}

void WebviewWindow::DestroyNow() {
  if (close_source_ != 0) {
    g_source_remove(close_source_);
    close_source_ = 0;
  }
  if (closed_ || window_ == nullptr) return;
  closing_ = true;
  composer_.BeginClose();
  DeliverClosing();
  // Emits destroy, whose handler releases this object.
  gtk_widget_destroy(window_);
}

void WebviewWindow::PublishNavigationState() {
  if (closing_ || closed_) return;
  auto *view = WEBKIT_WEB_VIEW(webview_);
  NavigationState next;
  next.can_go_back = webkit_web_view_can_go_back(view);
  next.can_go_forward = webkit_web_view_can_go_forward(view);
  next.is_loading = webkit_web_view_is_loading(view);
  const char *uri = webkit_web_view_get_uri(view);
  next.url = uri != nullptr ? uri : "";
  const char *title = webkit_web_view_get_title(view);
  next.title = title != nullptr ? title : "";
  if (published_ && next == navigation_) return;
  published_ = true;
  navigation_ = next;

  const char *url_value = navigation_.url.empty() ? nullptr : navigation_.url.c_str();
  const char *title_value =
      navigation_.title.empty() ? nullptr : navigation_.title.c_str();
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "canGoBack",
                           fl_value_new_bool(navigation_.can_go_back));
  fl_value_set_string_take(args, "canGoForward",
                           fl_value_new_bool(navigation_.can_go_forward));
  fl_value_set_string_take(args, "isLoading",
                           fl_value_new_bool(navigation_.is_loading));
  fl_value_set_string_take(
      args, "url", url_value ? fl_value_new_string(url_value) : fl_value_new_null());
  fl_value_set_string_take(
      args, "title",
      title_value ? fl_value_new_string(title_value) : fl_value_new_null());
  Emit("onNavigationStateChanged", args);

  const DWWNavigationState state{window_id_,
                                 navigation_.can_go_back,
                                 navigation_.can_go_forward,
                                 navigation_.is_loading,
                                 url_value,
                                 title_value};
  composer_.NavigationChanged(state);
}

bool WebviewWindow::GoForward() {
  if (closing_ || closed_) return false;
  webkit_web_view_go_forward(WEBKIT_WEB_VIEW(webview_));
  return true;
}

bool WebviewWindow::GoBack() {
  if (closing_ || closed_) return false;
  webkit_web_view_go_back(WEBKIT_WEB_VIEW(webview_));
  return true;
}

bool WebviewWindow::Reload() {
  if (closing_ || closed_) return false;
  webkit_web_view_reload(WEBKIT_WEB_VIEW(webview_));
  return true;
}

bool WebviewWindow::Stop() {
  if (closing_ || closed_) return false;
  webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(webview_));
  return true;
}

namespace {

void RespondError(FlMethodCall *call, const char *code, const char *message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

}  // namespace

void WebviewWindow::GetAllCookies(FlMethodCall *call) {
  if (closing_ || closed_) {
    RespondError(call, "browser_closed", "The browser has closed");
    return;
  }
  auto *manager = webkit_web_context_get_cookie_manager(
      webkit_web_view_get_context(WEBKIT_WEB_VIEW(webview_)));
  webkit_cookie_manager_get_cookies(
      manager, webkit_web_view_get_uri(WEBKIT_WEB_VIEW(webview_)),
      javascript_cancellable_,
      [](GObject *object, GAsyncResult *res, gpointer user_data) {
        g_autoptr(FlMethodCall) call = FL_METHOD_CALL(user_data);
        g_autoptr(GError) error = nullptr;
        GList *cookies = webkit_cookie_manager_get_cookies_finish(
            WEBKIT_COOKIE_MANAGER(object), res, &error);
        if (error != nullptr) {
          RespondError(call, "cookies_failed", error->message);
          return;
        }
        g_autoptr(FlValue) list = fl_value_new_list();
        for (GList *l = cookies; l; l = l->next) {
          auto *cookie = static_cast<SoupCookie *>(l->data);
          g_autoptr(FlValue) map = fl_value_new_map();
          fl_value_set_string_take(map, "name",
                                   fl_value_new_string(soup_cookie_get_name(cookie)));
          fl_value_set_string_take(map, "value",
                                   fl_value_new_string(soup_cookie_get_value(cookie)));
          fl_value_set_string_take(map, "domain",
                                   fl_value_new_string(soup_cookie_get_domain(cookie)));
          fl_value_set_string_take(map, "path",
                                   fl_value_new_string(soup_cookie_get_path(cookie)));
          auto *expiration = soup_cookie_get_expires(cookie);
          if (expiration != nullptr) {
#if SOUP_MAJOR_VERSION >= 3
            const gdouble expires = g_date_time_to_unix(expiration);
#else
            const gdouble expires = soup_date_to_time_t(expiration);
#endif
            fl_value_set_string_take(map, "expires", fl_value_new_float(expires));
          } else {
            fl_value_set_string_take(map, "expires", fl_value_new_null());
          }
          fl_value_set_string_take(map, "httpOnly",
                                   fl_value_new_bool(soup_cookie_get_http_only(cookie)));
          fl_value_set_string_take(map, "secure",
                                   fl_value_new_bool(soup_cookie_get_secure(cookie)));
          fl_value_set_string_take(map, "sessionOnly",
                                   fl_value_new_bool(expiration == nullptr));
          fl_value_append(list, map);
        }
        g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
        fl_method_call_respond_success(call, list, nullptr);
      },
      g_object_ref(call));
}

gboolean WebviewWindow::DecidePolicy(WebKitPolicyDecision *decision,
                                     WebKitPolicyDecisionType type) {
  if (closing_ || closed_) return false;
  if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
    // WebKit ignores main documents it cannot show; download them instead,
    // as on macOS and Windows.
    auto *response_decision = WEBKIT_RESPONSE_POLICY_DECISION(decision);
#ifndef WEBKIT_OLD_USED
    if (!webkit_response_policy_decision_is_main_frame_main_resource(
            response_decision)) {
      return false;
    }
#endif
    if (webkit_response_policy_decision_is_mime_type_supported(
            response_decision) &&
        !is_attachment(
            webkit_response_policy_decision_get_response(response_decision))) {
      return false;
    }
    webkit_policy_decision_download(decision);
    return true;
  }
  // Only top-level navigations are decided, as on the other platforms.
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) return false;
  if (skip_next_decision_) {
    skip_next_decision_ = false;
    return false;
  }
  if (!url_request_enabled_ || !request_navigation_) return false;
  auto *navigation_action = webkit_navigation_policy_decision_get_navigation_action(
      WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  auto *request = webkit_navigation_action_get_request(navigation_action);
  const char *uri = webkit_uri_request_get_uri(request);
  if (uri == nullptr) return false;
  // WebKit waits until the referenced decision is used or ignored.
  request_navigation_(uri, decision);
  return true;
}

void WebviewWindow::EvaluateJavaScript(const char *java_script,
                                       FlMethodCall *call) {
  if (closing_ || closed_) {
    RespondError(call, "browser_closed", "The browser has closed");
    return;
  }
#ifdef WEBKIT_OLD_USED
  webkit_web_view_run_javascript(
#else
  webkit_web_view_evaluate_javascript(
#endif
      WEBKIT_WEB_VIEW(webview_), java_script,
#ifndef WEBKIT_OLD_USED
      -1, nullptr, nullptr,
#endif
      javascript_cancellable_,
      [](GObject *object, GAsyncResult *result, gpointer user_data) {
        g_autoptr(FlMethodCall) call = FL_METHOD_CALL(user_data);
        GError *error = nullptr;
        auto *js_result =
#ifdef WEBKIT_OLD_USED
            webkit_web_view_run_javascript_finish(
#else
            webkit_web_view_evaluate_javascript_finish(
#endif
                WEBKIT_WEB_VIEW(object), result, &error);
        if (!js_result) {
          RespondError(call, "javascript_error",
                       error ? error->message : "Unknown error");
          g_clear_error(&error);
        } else {
          g_autofree gchar *js_value = jsc_value_to_json(
#ifdef WEBKIT_OLD_USED
              webkit_javascript_result_get_js_value
#endif
              (js_result),
              0);
          g_autoptr(FlValue) value =
              js_value ? fl_value_new_string(js_value) : nullptr;
          fl_method_call_respond_success(call, value, nullptr);
#ifdef WEBKIT_OLD_USED
          webkit_javascript_result_unref(js_result);
#else
          g_object_unref(js_result);
#endif
        }
      },
      g_object_ref(call));
}

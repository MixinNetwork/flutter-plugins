//
// Created by boyan on 10/21/21.
//

#include "webview_window.h"
#include <utility>
#include <unordered_map>
#include <string>

#if WEBKIT_MAJOR_VERSION < 2 || \
    (WEBKIT_MAJOR_VERSION == 2 && WEBKIT_MINOR_VERSION < 40)
#define WEBKIT_OLD_USED
#endif

void get_cookies_callback(WebKitCookieManager *manager, GAsyncResult *res,
                          gpointer user_data) {
  CookieData *data = (CookieData *)user_data;
  GError *error = NULL;

  GList *cookies =
      webkit_cookie_manager_get_cookies_finish(manager, res, &error);
  if (error != NULL) {
    g_print("Error getting cookies: %s\n", error->message);
    g_error_free(error);
    data->cookies = NULL;
  } else {
    data->cookies = cookies;
  }

  g_main_loop_quit(data->loop);
}

GList *get_cookies_sync(WebKitWebView *web_view) {
  WebKitCookieManager *cookie_manager;
  GMainLoop *loop;
  CookieData data = {};

  cookie_manager = webkit_web_context_get_cookie_manager(
      webkit_web_view_get_context(web_view));
  loop = g_main_loop_new(NULL, FALSE);
  data.loop = loop;

  const gchar *uri = webkit_web_view_get_uri(web_view);

  // Start the asynchronous operation
  webkit_cookie_manager_get_cookies(cookie_manager, uri, NULL,
                                    (GAsyncReadyCallback)get_cookies_callback,
                                    &data);

  // Run the main loop until the callback is called
  g_main_loop_run(loop);

  g_main_loop_unref(loop);

  return data.cookies;
}

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
  // Handing back web_view itself aborts in WebCore on some builds, so open
  // user-clicked links in the same view and drop script-opened windows.
  if (webkit_navigation_action_is_user_gesture(navigation_action)) {
    webkit_web_view_load_request(
        web_view, webkit_navigation_action_get_request(navigation_action));
  }
  return nullptr;
}

void on_load_changed(WebKitWebView *web_view, WebKitLoadEvent load_event,
                     gpointer user_data) {
  auto *window = static_cast<WebviewWindow *>(user_data);
  window->OnLoadChanged(load_event);
}

gboolean decide_policy_cb(WebKitWebView *web_view,
                          WebKitPolicyDecision *decision,
                          WebKitPolicyDecisionType type, gpointer user_data) {
  auto *window = static_cast<WebviewWindow *>(user_data);
  return window->DecidePolicy(decision, type);
}

}  // namespace

WebviewWindow::WebviewWindow(FlMethodChannel *method_channel, int64_t window_id,
                             std::function<void()> on_close_callback,
                             const std::string &title, int width, int height,
                             int title_bar_height, int title_bar_top_padding,
                             TitleBarViews *title_bar_views, GtkWindow *parent,
                             bool show_system_title_bar)
    : method_channel_(method_channel),
      window_id_(window_id),
      on_close_callback_(std::move(on_close_callback)),
      default_user_agent_(),
      title_bar_views_(title_bar_views) {
  g_object_ref(method_channel_);

  javascript_cancellable_ = g_cancellable_new();
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_decorated(GTK_WINDOW(window_), show_system_title_bar);
  if (parent != nullptr) {
    // Declared as a child of the app window, so window managers treat it like
    // a dialog: centred over the app and kept above it on stacking ones,
    // floated instead of tiled on tiling ones.
    gtk_window_set_transient_for(GTK_WINDOW(window_), parent);
  }
  g_object_ref_sink(window_);
  g_signal_connect(G_OBJECT(window_), "destroy",
                   G_CALLBACK(+[](GtkWidget *, gpointer arg) {
                     auto *window = static_cast<WebviewWindow *>(arg);
                     window->OnDestroyed();
                   }),
                   this);
  gtk_window_set_title(GTK_WINDOW(window_), title.c_str());
  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_window_set_position(GTK_WINDOW(window_),
                          parent != nullptr ? GTK_WIN_POS_CENTER_ON_PARENT
                                            : GTK_WIN_POS_CENTER);

  box_ = GTK_BOX(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0));
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(box_));

  FlView *title_bar = nullptr;
  if (title_bar_height > 0) {
    title_bar = title_bar_views_->CreateView(window_id, title_bar_top_padding);
    title_bar_view_id_ = fl_view_get_id(title_bar);
    g_debug("desktop_webview_window toolbar webview=%" G_GINT64_FORMAT
            " engine=%p view=%" G_GINT64_FORMAT,
            window_id, fl_view_get_engine(title_bar), fl_view_get_id(title_bar));
    g_signal_connect(title_bar, "first-frame",
                     G_CALLBACK(+[](FlView *view, gpointer) {
                       g_debug("desktop_webview_window toolbar first-frame "
                               "engine=%p view=%" G_GINT64_FORMAT,
                               fl_view_get_engine(view), fl_view_get_id(view));
                     }), nullptr);
    gtk_widget_set_size_request(GTK_WIDGET(title_bar), -1, title_bar_height);
    gtk_widget_set_vexpand(GTK_WIDGET(title_bar), FALSE);
    gtk_box_pack_start(box_, GTK_WIDGET(title_bar), FALSE, FALSE, 0);
  }

  // initial web_view
  webview_ = webkit_web_view_new();
  g_object_ref_sink(webview_);
  content_manager_ = WEBKIT_USER_CONTENT_MANAGER(g_object_ref(
      webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_))));
  g_signal_connect(G_OBJECT(webview_), "load-failed-with-tls-errors",
                   G_CALLBACK(on_load_failed_with_tls_errors), this);
  g_signal_connect(G_OBJECT(webview_), "create", G_CALLBACK(on_create), this);
  g_signal_connect(G_OBJECT(webview_), "load-changed",
                   G_CALLBACK(on_load_changed), this);
  g_signal_connect(G_OBJECT(webview_), "decide-policy",
                   G_CALLBACK(decide_policy_cb), this);

  auto settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_javascript_can_open_windows_automatically(settings, true);
  default_user_agent_ = webkit_settings_get_user_agent(settings);
  gtk_box_pack_end(box_, webview_, true, true, 0);

  gtk_widget_show_all(GTK_WIDGET(window_));
  gtk_widget_grab_focus(GTK_WIDGET(webview_));

  // FROM: https://github.com/leanflutter/window_manager/pull/343
  // Disconnect all delete-event handlers first in flutter 3.10.1, which causes
  // delete_event not working. Issues from flutter/engine:
  // https://github.com/flutter/engine/pull/40033
  gulong handler_id = title_bar == nullptr ? 0 : g_signal_handler_find(window_, G_SIGNAL_MATCH_DATA, 0, 0,
                                           NULL, NULL, title_bar);
  if (handler_id > 0) {
    g_signal_handler_disconnect(window_, handler_id);
  }
}

WebviewWindow::~WebviewWindow() {
  // The plugin can also dispose a still-open window during engine shutdown.
  // Remove callbacks first so GTK destruction cannot re-enter its owner map.
  on_close_callback_ = nullptr;
  DisconnectCallbacks();
  if (window_ != nullptr) {
    g_signal_handlers_disconnect_by_data(window_, this);
    gtk_widget_destroy(window_);
    g_clear_object(&window_);
  }
  g_clear_object(&webview_);
  g_clear_object(&content_manager_);
  g_clear_object(&javascript_cancellable_);
  g_clear_object(&method_channel_);
}

void WebviewWindow::DisconnectCallbacks() {
  if (javascript_cancellable_ != nullptr) {
    g_cancellable_cancel(javascript_cancellable_);
  }
  if (webview_ != nullptr) {
    g_signal_handlers_disconnect_by_data(webview_, this);
  }
  if (content_manager_ != nullptr) {
    for (const auto &entry : js_channel_handler_ids_) {
      g_signal_handler_disconnect(content_manager_, entry.second);
      webkit_user_content_manager_unregister_script_message_handler(
          content_manager_, entry.first.c_str());
    }
    js_channel_handler_ids_.clear();
  }
  if (title_bar_views_ != nullptr && title_bar_view_id_ >= 0) {
    title_bar_views_->RemoveView(title_bar_view_id_);
    title_bar_view_id_ = -1;
  }
}

void WebviewWindow::OnDestroyed() {
  if (closed_) return;
  closed_ = true;
  closing_ = true;
  DisconnectCallbacks();

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_int(window_id_));
  fl_method_channel_invoke_method(method_channel_, "onWindowClose", args,
                                  nullptr, nullptr, nullptr);

  // This erases the owning unique_ptr. Move the callable off the object and
  // perform ALL member access, notifications and cleanup before invoking it.
  // In particular, do not read window_id_ or method_channel_ after this call.
  auto on_close = std::move(on_close_callback_);
  if (on_close) on_close();
}

void WebviewWindow::Navigate(const char *url) {
  if (closing_ || closed_) return;
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

void WebviewWindow::Close() {
  if (closing_ || closed_ || window_ == nullptr) return;
  closing_ = true;
  gtk_widget_destroy(window_);
}

void WebviewWindow::OnLoadChanged(WebKitLoadEvent load_event) {
  if (closing_ || closed_) return;
  // notify history changed event.
  {
    auto can_go_back = webkit_web_view_can_go_back(WEBKIT_WEB_VIEW(webview_));
    auto can_go_forward =
        webkit_web_view_can_go_forward(WEBKIT_WEB_VIEW(webview_));
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_take(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
    fl_value_set_take(args, fl_value_new_string("canGoBack"),
                 fl_value_new_bool(can_go_back));
    fl_value_set_take(args, fl_value_new_string("canGoForward"),
                 fl_value_new_bool(can_go_forward));
    fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                    "onHistoryChanged", args, nullptr, nullptr,
                                    nullptr);
  }

  // notify load start/finished event.
  switch (load_event) {
    case WEBKIT_LOAD_STARTED: {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_take(args, fl_value_new_string("id"),
                   fl_value_new_int(window_id_));
      fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                      "onNavigationStarted", args, nullptr,
                                      nullptr, nullptr);
      break;
    }
    case WEBKIT_LOAD_FINISHED: {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_take(args, fl_value_new_string("id"),
                   fl_value_new_int(window_id_));
      fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                      "onNavigationCompleted", args, nullptr,
                                      nullptr, nullptr);
      break;
    }
    default:
      break;
  }
}

void WebviewWindow::GoForward() {
  if (closing_ || closed_) return;
  webkit_web_view_go_forward(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::GoBack() {
  if (closing_ || closed_) return;
  webkit_web_view_go_back(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::Reload() {
  if (closing_ || closed_) return;
  webkit_web_view_reload(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::StopLoading() {
  if (closing_ || closed_) return;
  webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(webview_));
}

FlValue *WebviewWindow::GetAllCookies() {
  GList *cookies = get_cookies_sync(WEBKIT_WEB_VIEW(webview_));

  g_autoptr(FlValue) fl_cookie_list = fl_value_new_list();

  FlValue* cookie_list = fl_value_ref(fl_cookie_list);

  for (GList *l = cookies; l; l = l->next) {
    SoupCookie *cookie = (SoupCookie *)l->data;
    g_autoptr(FlValue) cookie_map = fl_value_new_map();

    fl_value_set_string_take(cookie_map, "name",
                             fl_value_new_string(soup_cookie_get_name(cookie)));
    fl_value_set_string_take(
        cookie_map, "value",
        fl_value_new_string(soup_cookie_get_value(cookie)));
    fl_value_set_string_take(
        cookie_map, "domain",
        fl_value_new_string(soup_cookie_get_domain(cookie)));
    fl_value_set_string_take(cookie_map, "path",
                             fl_value_new_string(soup_cookie_get_path(cookie)));

    auto *expiration = soup_cookie_get_expires(cookie);

    if (expiration != nullptr) {
#if SOUP_MAJOR_VERSION >= 3
      const gdouble expires = g_date_time_to_unix(expiration);
#else
      const gdouble expires = soup_date_to_time_t(expiration);
#endif
      fl_value_set_string_take(cookie_map, "expires",
                               fl_value_new_float(expires));
    } else {
      fl_value_set_string_take(cookie_map, "expires", fl_value_new_null());
    }

    fl_value_set_string_take(
        cookie_map, "httpOnly",
        fl_value_new_bool(soup_cookie_get_http_only(cookie)));
    fl_value_set_string_take(cookie_map, "secure",
                             fl_value_new_bool(soup_cookie_get_secure(cookie)));
    fl_value_set_string_take(cookie_map, "sessionOnly",
                             fl_value_new_bool(false));

    fl_value_append(cookie_list, cookie_map);
    soup_cookie_free(cookie);
  }

  g_list_free(cookies);

  return cookie_list;
}

gboolean WebviewWindow::DecidePolicy(WebKitPolicyDecision *decision,
                                     WebKitPolicyDecisionType type) {
  if (closing_ || closed_) return false;
  if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    auto *navigation_decision = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
    auto *navigation_action =
        webkit_navigation_policy_decision_get_navigation_action(
            navigation_decision);
    auto *request = webkit_navigation_action_get_request(navigation_action);
    auto *uri = webkit_uri_request_get_uri(request);
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_take(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
    fl_value_set_take(args, fl_value_new_string("url"), fl_value_new_string(uri));
    fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                    "onUrlRequested", args, nullptr, nullptr,
                                    nullptr);
  }
  return false;
}

void WebviewWindow::EvaluateJavaScript(const char *java_script,
                                       FlMethodCall *call) {
  if (closing_ || closed_) {
    fl_method_call_respond_error(call, "closed", "Webview has closed", nullptr,
                                 nullptr);
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
        auto *call = static_cast<FlMethodCall *>(user_data);
        GError *error = nullptr;
        auto *js_result =
#ifdef WEBKIT_OLD_USED
            webkit_web_view_run_javascript_finish(
#else
            webkit_web_view_evaluate_javascript_finish(
#endif
                WEBKIT_WEB_VIEW(object), result, &error);
        if (!js_result) {
          fl_method_call_respond_error(call, "failed to evaluate javascript.",
                                       error ? error->message : "Unknown error",
                                       nullptr, nullptr);
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
        g_object_unref(call);
      },
      g_object_ref(call));
}

void WebviewWindow::RegisterJavaScriptChannel(const std::string &name) {
  if (closing_ || closed_) return;
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    struct HandlerData {
        WebviewWindow *self;
        std::string name;
    };

    HandlerData *data = new HandlerData{this, name};
    auto it = js_channel_handler_ids_.find(name);
    if (it != js_channel_handler_ids_.end()) {
        g_signal_handler_disconnect(manager, it->second);
        js_channel_handler_ids_.erase(it);
        webkit_user_content_manager_unregister_script_message_handler(
            manager, name.c_str());
    }
    webkit_user_content_manager_register_script_message_handler(
        manager, name.c_str());

    gulong handler_id = g_signal_connect_data(
            manager,
            ("script-message-received::" + name).c_str(),
            G_CALLBACK(+[](WebKitUserContentManager *manager,
                           WebKitJavascriptResult *result,
                           gpointer user_data) {
                HandlerData *data = static_cast<HandlerData *>(user_data);
                WebviewWindow *self = data->self;
                if (self->closing_ || self->closed_) return;
                const std::string &handler_name = data->name;

                JSCValue *value = webkit_javascript_result_get_js_value(result);

                if (jsc_value_is_string(value)) {
                    gchar *str_value = jsc_value_to_string(value);
                    if (str_value != nullptr) {
                        g_autoptr(FlValue) args = fl_value_new_map();
                        fl_value_set_string_take(args, "name",
                                            fl_value_new_string(handler_name.c_str()));
                        fl_value_set_string_take(args, "body",
                                            fl_value_new_string(str_value));
                        fl_value_set_string_take(args, "id",
                                            fl_value_new_int(self->window_id_));

                        fl_method_channel_invoke_method(
                                self->method_channel_,
                                "onJavaScriptMessage",
                                args,
                                nullptr,
                                nullptr,
                                nullptr);

                        g_free(str_value);
                    }
                }
            }),
            data,
            +[](gpointer user_data, GClosure *) {
                delete static_cast<HandlerData *>(user_data);
            },
            static_cast<GConnectFlags>(0));

    js_channel_handler_ids_[name] = handler_id;
}


void WebviewWindow::UnregisterJavaScriptChannel(const std::string &name) {
  if (closing_ || closed_) return;
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    auto it = js_channel_handler_ids_.find(name);
    if (it != js_channel_handler_ids_.end()) {
        g_signal_handler_disconnect(manager, it->second);
        js_channel_handler_ids_.erase(it);
    }

    webkit_user_content_manager_unregister_script_message_handler(
            manager, name.c_str());
}


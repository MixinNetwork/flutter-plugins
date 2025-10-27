//
// Created by boyan on 10/21/21.
//

#include "webview_window.h"

#include <utility>

#include "message_channel_plugin.h"

#if WEBKIT_MAJOR_VERSION < 2 || \
    (WEBKIT_MAJOR_VERSION == 2 && WEBKIT_MINOR_VERSION < 40)
#define WEBKIT_OLD_USED
#endif

void get_cookies_callback(WebKitCookieManager *manager, GAsyncResult *res,
                          gpointer user_data) {
    CookieData *data = (CookieData *) user_data;
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
    CookieData data = {0};

    cookie_manager = webkit_web_context_get_cookie_manager(
            webkit_web_view_get_context(web_view));
    loop = g_main_loop_new(NULL, FALSE);
    data.loop = loop;

    const gchar *uri = webkit_web_view_get_uri(web_view);

    // Start the asynchronous operation
    webkit_cookie_manager_get_cookies(cookie_manager, uri, NULL,
                                      (GAsyncReadyCallback) get_cookies_callback,
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
        return GTK_WIDGET(web_view);
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
                             int title_bar_height)
        : method_channel_(method_channel),
          window_id_(window_id),
          on_close_callback_(std::move(on_close_callback)),
          default_user_agent_() {
    g_object_ref(method_channel_);

    window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    g_signal_connect(G_OBJECT(window_), "destroy",
                     G_CALLBACK(+[](GtkWidget *, gpointer arg) {
                         auto *window = static_cast<WebviewWindow *>(arg);
                         if (window->on_close_callback_) {
                             window->on_close_callback_();
                         }
                         auto *args = fl_value_new_map();
                         fl_value_set(args, fl_value_new_string("id"),
                                      fl_value_new_int(window->window_id_));
                         fl_method_channel_invoke_method(
                                 FL_METHOD_CHANNEL(window->method_channel_),
                                 "onWindowClose", args, nullptr, nullptr, nullptr);
                     }),
                     this);
    gtk_window_set_title(GTK_WINDOW(window_), title.c_str());
    gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
    gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);

    box_ = GTK_BOX(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0));
    gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(box_));

    // initial flutter_view
    g_autoptr(FlDartProject)
    project = fl_dart_project_new();
    const char *args[] = {"web_view_title_bar", g_strdup_printf("%ld", window_id),
                          nullptr};
    fl_dart_project_set_dart_entrypoint_arguments(project,
                                                  const_cast<char **>(args));
    auto *title_bar = fl_view_new(project);

    g_autoptr(FlPluginRegistrar)
    desktop_webview_window_registrar =
            fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(title_bar),
                                                        "DesktopWebviewWindowPlugin");
    client_message_channel_plugin_register_with_registrar(
            desktop_webview_window_registrar);

    gtk_widget_set_size_request(GTK_WIDGET(title_bar), -1, title_bar_height);
    gtk_widget_set_vexpand(GTK_WIDGET(title_bar), FALSE);
    gtk_box_pack_start(box_, GTK_WIDGET(title_bar), FALSE, FALSE, 0);

    // initial web_view
    webview_ = webkit_web_view_new();
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
    guint handler_id = g_signal_handler_find(window_, G_SIGNAL_MATCH_DATA, 0, 0,
                                             NULL, NULL, title_bar);
    if (handler_id > 0) {
        g_signal_handler_disconnect(window_, handler_id);
    }
}

WebviewWindow::~WebviewWindow() {
    g_object_unref(method_channel_);
    printf("~WebviewWindow\n");
}

void WebviewWindow::Navigate(const char *url) {
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview_), url);
}

void WebviewWindow::RunJavaScriptWhenContentReady(const char *java_script) {
    auto *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));
    webkit_user_content_manager_add_script(
            manager,
            webkit_user_script_new(java_script, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                                   WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
                                   nullptr, nullptr));
}

void WebviewWindow::SetApplicationNameForUserAgent(
        const std::string &app_name) {
    auto *setting = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
    webkit_settings_set_user_agent(setting,
                                   (default_user_agent_ + app_name).c_str());
}

void WebviewWindow::Close() { gtk_window_close(GTK_WINDOW(window_)); }

void WebviewWindow::OnLoadChanged(WebKitLoadEvent load_event) {
    // notify history changed event.
    {
        auto can_go_back = webkit_web_view_can_go_back(WEBKIT_WEB_VIEW(webview_));
        auto can_go_forward =
                webkit_web_view_can_go_forward(WEBKIT_WEB_VIEW(webview_));
        auto *args = fl_value_new_map();
        fl_value_set(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
        fl_value_set(args, fl_value_new_string("canGoBack"),
                     fl_value_new_bool(can_go_back));
        fl_value_set(args, fl_value_new_string("canGoForward"),
                     fl_value_new_bool(can_go_forward));
        fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                        "onHistoryChanged", args, nullptr, nullptr,
                                        nullptr);
    }

    // notify load start/finished event.
    switch (load_event) {
        case WEBKIT_LOAD_STARTED: {
            auto *args = fl_value_new_map();
            fl_value_set(args, fl_value_new_string("id"),
                         fl_value_new_int(window_id_));
            fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                            "onNavigationStarted", args, nullptr,
                                            nullptr, nullptr);
            break;
        }
        case WEBKIT_LOAD_FINISHED: {
            auto *args = fl_value_new_map();
            fl_value_set(args, fl_value_new_string("id"),
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
    webkit_web_view_go_forward(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::GoBack() {
    webkit_web_view_go_back(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::Reload() {
    webkit_web_view_reload(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::StopLoading() {
    webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(webview_));
}

FlValue *WebviewWindow::GetAllCookies() {
    GList *cookies = get_cookies_sync(WEBKIT_WEB_VIEW(webview_));

    g_autoptr(FlValue)
    fl_cookie_list = fl_value_new_list();

    FlValue *cookie_list = fl_value_ref(fl_cookie_list);

    for (GList *l = cookies; l; l = l->next) {
        SoupCookie *cookie = (SoupCookie *) l->data;
        g_autoptr(FlValue)
        cookie_map = fl_value_new_map();

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

        gdouble expires = g_date_time_get_seconds(soup_cookie_get_expires(cookie));

        if (expires >= 0) {
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

    g_free(cookies);

    return cookie_list;
}

gboolean WebviewWindow::DecidePolicy(WebKitPolicyDecision *decision,
                                     WebKitPolicyDecisionType type) {
    if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
        auto *navigation_decision = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
        auto *navigation_action =
                webkit_navigation_policy_decision_get_navigation_action(
                        navigation_decision);
        auto *request = webkit_navigation_action_get_request(navigation_action);
        auto *uri = webkit_uri_request_get_uri(request);
        auto *args = fl_value_new_map();
        fl_value_set(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
        fl_value_set(args, fl_value_new_string("url"), fl_value_new_string(uri));
        fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                        "onUrlRequested", args, nullptr, nullptr,
                                        nullptr);
    }
    return false;
}

void WebviewWindow::EvaluateJavaScript(const char *java_script,
                                       FlMethodCall *call) {
#ifdef WEBKIT_OLD_USED
    webkit_web_view_run_javascript(
#else
            webkit_web_view_evaluate_javascript(
#endif
            WEBKIT_WEB_VIEW(webview_), java_script,
#ifndef WEBKIT_OLD_USED
            -1, nullptr, nullptr,
#endif
            nullptr,
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
                                                 error->message, nullptr, nullptr);
                    g_error_free(error);
                } else {
                    auto *js_value = jsc_value_to_json(
#ifdef WEBKIT_OLD_USED
                            webkit_javascript_result_get_js_value
#endif
                                    (js_result),
                            0);
                    fl_method_call_respond_success(
                            call, js_value ? fl_value_new_string(js_value) : nullptr,
                            nullptr);
                }
                g_object_unref(call);
            },
            g_object_ref(call));
}

void WebviewWindow::RegisterJavaScriptChannel(const std::string &name) {
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    webkit_user_content_manager_register_script_message_handler(manager, name.c_str());

    struct HandlerData {
        WebviewWindow *self;
        std::string name;
    };

    HandlerData *data = new HandlerData{this, name};

    g_signal_connect_data(
            manager,
            ("script-message-received::" + name).c_str(),
            G_CALLBACK(+[](WebKitUserContentManager *manager,
                           WebKitJavascriptResult *result,
                           gpointer user_data) {
                HandlerData *data = static_cast<HandlerData *>(user_data);
                WebviewWindow *self = data->self;
                const std::string &handler_name = data->name;

                JSCValue *value = webkit_javascript_result_get_js_value(result);

                if (jsc_value_is_string(value)) {
                    gchar *str_value = jsc_value_to_string(value);
                    if (str_value != nullptr) {
                        FlValue *args = fl_value_new_map();
                        fl_value_set_string(args, "name",
                                            fl_value_new_string(handler_name.c_str()));
                        fl_value_set_string(args, "body", fl_value_new_string(str_value));
                        fl_value_set_string(args, "id", fl_value_new_int(self->window_id_));

                        fl_method_channel_invoke_method(
                                self->method_channel_,
                                "onJavaScriptMessage",
                                args,
                                nullptr,  // cancellable
                                nullptr,  // callback
                                nullptr); // user_data

                        g_free(str_value);
                    }
                }
            }),
            data,
            +[](gpointer user_data, GClosure *) {
                delete static_cast<HandlerData *>(user_data);
            },
            static_cast<GConnectFlags>(0));
}

void WebviewWindow::UnregisterJavaScriptChannel(const std::string &name) {
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    webkit_user_content_manager_unregister_script_message_handler(manager, name.c_str());
}

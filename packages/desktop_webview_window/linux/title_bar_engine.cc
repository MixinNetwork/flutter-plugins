#include "title_bar_engine.h"

#include <cstring>

#include "message_channel_plugin.h"

TitleBarEngine::~TitleBarEngine() {
  // No callback may retain this host after its owner starts disposing it.
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&channel_);
  }
  if (engine_window_ != nullptr) {
    gtk_widget_destroy(engine_window_);
    g_clear_object(&engine_window_);
  }
  g_clear_object(&engine_);
}

void TitleBarEngine::EnsureStarted() {
  if (engine_ != nullptr) return;

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char* arguments[] = {"web_view_title_bar", "shared", nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<char**>(arguments));

  // The public Linux embedding starts a non-headless engine when its implicit
  // view is realized. fl_engine_new + fl_view_new_for_engine alone cannot start
  // it. Keep that bootstrap view realized but unmapped so closing any browser
  // (including the first or last one) cannot dispose the implicit view.
  FlView* implicit_view = fl_view_new(project);
  engine_ = FL_ENGINE(g_object_ref(fl_view_get_engine(implicit_view)));
  g_debug("desktop_webview_window shared toolbar engine=%p", engine_);
  engine_window_ = gtk_window_new(GTK_WINDOW_POPUP);
  g_object_ref_sink(engine_window_);
  gtk_window_set_default_size(GTK_WINDOW(engine_window_), 1, 1);
  gtk_container_add(GTK_CONTAINER(engine_window_), GTK_WIDGET(implicit_view));

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(
          FL_PLUGIN_REGISTRY(implicit_view), "DesktopWebviewWindowPlugin");
  client_message_channel_plugin_register_with_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(fl_engine_get_binary_messenger(engine_),
                                  "desktop_webview_window/titlebars",
                                  FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel_,
      [](FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
        auto* self = static_cast<TitleBarEngine*>(user_data);
        const char* method = fl_method_call_get_name(call);
        if (strcmp(method, "getViews") == 0) {
          g_autoptr(FlValue) views = self->GetViews();
          fl_method_call_respond_success(call, views, nullptr);
        } else if (strcmp(method, "ready") == 0) {
          fl_method_call_respond_success(call, nullptr, nullptr);
          self->NotifyViewsChanged();
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      this, nullptr);

  gtk_widget_realize(engine_window_);
  gtk_widget_realize(GTK_WIDGET(implicit_view));
}

FlView* TitleBarEngine::CreateView(int64_t webview_id,
                                  int title_bar_top_padding) {
  EnsureStarted();
  FlView* view = fl_view_new_for_engine(engine_);
  const int64_t view_id = fl_view_get_id(view);
  views_.emplace(view_id,
                 ViewConfiguration{webview_id, title_bar_top_padding});
  NotifyViewsChanged();
  return view;
}

void TitleBarEngine::RemoveView(int64_t view_id) {
  if (views_.erase(view_id) != 0) NotifyViewsChanged();
}

FlValue* TitleBarEngine::GetViews() const {
  FlValue* result = fl_value_new_list();
  for (const auto& entry : views_) {
    g_autoptr(FlValue) configuration = fl_value_new_map();
    fl_value_set_string_take(configuration, "viewId",
                             fl_value_new_int(entry.first));
    fl_value_set_string_take(configuration, "webViewId",
                             fl_value_new_int(entry.second.webview_id));
    fl_value_set_string_take(
        configuration, "titleBarTopPadding",
        fl_value_new_int(entry.second.title_bar_top_padding));
    fl_value_append(result, configuration);
  }
  return result;
}

void TitleBarEngine::NotifyViewsChanged() {
  fl_method_channel_invoke_method(channel_, "viewsChanged", nullptr, nullptr,
                                  nullptr, nullptr);
}

#include "title_bar_views.h"

#include <cstring>

TitleBarViews::~TitleBarViews() {
  // No callback may retain this host after its owner starts disposing it.
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&channel_);
  }
}

TitleBarViews::TitleBarViews(FlBinaryMessenger* messenger, FlView* main_view) {
  if (main_view != nullptr) {
    engine_ = fl_view_get_engine(main_view);
    main_view_id_ = fl_view_get_id(main_view);
  }
  g_object_set_data(G_OBJECT(messenger), "desktop_webview_window/titlebars", this);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger,
                                  "desktop_webview_window/titlebars",
                                  FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel_,
      [](FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
        auto* self = static_cast<TitleBarViews*>(user_data);
        const char* method = fl_method_call_get_name(call);
        if (strcmp(method, "initialize") == 0) {
          if (self->engine_ == nullptr) {
            fl_method_call_respond_error(call, "titlebar_engine_missing",
                "Headless runners must call desktop_webview_window_plugin_attach_engine after registering plugins",
                nullptr, nullptr);
          } else {
            fl_method_call_respond_success(call, nullptr, nullptr);
          }
        } else if (strcmp(method, "getMainView") == 0) {
          g_autoptr(FlValue) id = self->main_view_id_ < 0
              ? nullptr : fl_value_new_int(self->main_view_id_);
          fl_method_call_respond_success(call, id, nullptr);
        } else if (strcmp(method, "getViews") == 0) {
          g_autoptr(FlValue) views = self->GetViews();
          fl_method_call_respond_success(call, views, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      this, nullptr);

}

void TitleBarViews::AttachEngine(FlEngine* engine) {
  engine_ = engine;
}

FlView* TitleBarViews::CreateView(int64_t webview_id,
                                  int title_bar_top_padding) {
  FlView* view = fl_view_new_for_engine(engine_);
  const int64_t view_id = fl_view_get_id(view);
  views_.emplace(view_id,
                 ViewConfiguration{webview_id, title_bar_top_padding});
  NotifyViewsChanged();
  return view;
}

void TitleBarViews::RemoveView(int64_t view_id) {
  if (views_.erase(view_id) != 0) NotifyViewsChanged();
}

FlValue* TitleBarViews::GetViews() const {
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

void TitleBarViews::NotifyViewsChanged() {
  fl_method_channel_invoke_method(channel_, "viewsChanged", nullptr, nullptr,
                                  nullptr, nullptr);
}

#ifndef DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_VIEWS_H_
#define DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_VIEWS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <map>

// Tracks browser titlebar views on the application-owned engine.
class TitleBarViews {
 public:
  TitleBarViews(FlBinaryMessenger* messenger, FlView* main_view);
  void AttachEngine(FlEngine* engine);
  ~TitleBarViews();

  FlView* CreateView(int64_t webview_id, int title_bar_top_padding);
  void RemoveView(int64_t view_id);

 private:
  struct ViewConfiguration {
    int64_t webview_id;
    int title_bar_top_padding;
  };

  void NotifyViewsChanged();
  FlValue* GetViews() const;

  FlEngine* engine_ = nullptr;  // Borrowed from the application.
  int64_t main_view_id_ = -1;
  FlMethodChannel* channel_ = nullptr;
  std::map<int64_t, ViewConfiguration> views_;
};

#endif  // DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_VIEWS_H_

#ifndef DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_ENGINE_H_
#define DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_ENGINE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <map>

// Experimental Linux multi-view host. The plugin owns one instance, created
// lazily only when a caller explicitly opts in. The implicit view is retained
// privately for the entire engine lifetime; browser windows own explicit views.
class TitleBarEngine {
 public:
  TitleBarEngine() = default;
  ~TitleBarEngine();

  FlView* CreateView(int64_t webview_id, int title_bar_top_padding);
  void RemoveView(int64_t view_id);

 private:
  struct ViewConfiguration {
    int64_t webview_id;
    int title_bar_top_padding;
  };

  void EnsureStarted();
  void NotifyViewsChanged();
  FlValue* GetViews() const;

  GtkWidget* engine_window_ = nullptr;
  FlEngine* engine_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  std::map<int64_t, ViewConfiguration> views_;
};

#endif  // DESKTOP_WEBVIEW_WINDOW_LINUX_TITLE_BAR_ENGINE_H_

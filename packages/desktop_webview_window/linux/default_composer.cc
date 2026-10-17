// The default composer: navigation buttons, the page title and its host in a
// GtkHeaderBar used as the window's title bar, the WebView below. It uses only
// the public composer API.

#include <gtk/gtk.h>

#include <map>
#include <memory>
#include <string>

#include "composer_runtime.h"

namespace {

struct TitleBar {
  int64_t browser;
  GtkWindow* window;
  uint32_t items;
  // CreateConfiguration.title, shown while the page has no title.
  std::string fallback_title;
  GtkWidget* header;
  GtkWidget* back = nullptr;
  GtkWidget* forward = nullptr;
  GtkWidget* reload = nullptr;
  bool loading = false;

  bool Has(DWWTitleBarItem item) const { return items & item; }
};

std::map<int64_t, std::unique_ptr<TitleBar>>& TitleBars() {
  static auto* title_bars = new std::map<int64_t, std::unique_ptr<TitleBar>>();
  return *title_bars;
}

GtkWidget* IconButton(const char* icon, TitleBar* title_bar,
                      void (*clicked)(GtkButton*, TitleBar*)) {
  GtkWidget* button = gtk_button_new_from_icon_name(icon, GTK_ICON_SIZE_BUTTON);
  gtk_widget_set_can_focus(button, FALSE);
  gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
  g_signal_connect(button, "clicked", G_CALLBACK(clicked), title_bar);
  return button;
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  auto* window = GTK_WINDOW(request->window);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(request->webview_view));

  auto title_bar = std::make_unique<TitleBar>();
  TitleBar* bar = title_bar.get();
  bar->browser = request->browser;
  bar->window = window;
  bar->items = request->title_bar;
  const char* title = gtk_window_get_title(window);
  bar->fallback_title = title != nullptr ? title : "";
  bar->header = gtk_header_bar_new();
  GtkHeaderBar* header = GTK_HEADER_BAR(bar->header);
  gtk_header_bar_set_show_close_button(header, TRUE);

  if (bar->Has(DWW_TITLE_BAR_NAVIGATION)) {
    bar->back = IconButton("go-previous-symbolic", bar,
                           +[](GtkButton*, TitleBar* t) {
                             dww_browser_go_back(t->browser);
                           });
    bar->forward = IconButton("go-next-symbolic", bar,
                              +[](GtkButton*, TitleBar* t) {
                                dww_browser_go_forward(t->browser);
                              });
    gtk_widget_set_sensitive(bar->back, FALSE);
    gtk_widget_set_sensitive(bar->forward, FALSE);
    // One segmented control, like GNOME Web's back and forward.
    GtkWidget* group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_style_context_add_class(gtk_widget_get_style_context(group), "linked");
    gtk_container_add(GTK_CONTAINER(group), bar->back);
    gtk_container_add(GTK_CONTAINER(group), bar->forward);
    gtk_header_bar_pack_start(header, group);
  }
  if (bar->Has(DWW_TITLE_BAR_RELOAD)) {
    bar->reload = IconButton("view-refresh-symbolic", bar,
                             +[](GtkButton*, TitleBar* t) {
                               if (t->loading) {
                                 dww_browser_stop(t->browser);
                               } else {
                                 dww_browser_reload(t->browser);
                               }
                             });
    gtk_header_bar_pack_start(header, bar->reload);
  }
  if (bar->Has(DWW_TITLE_BAR_TITLE) || bar->Has(DWW_TITLE_BAR_HOST)) {
    // Reserve the second line so the bar keeps its height on pages without a
    // host.
    gtk_header_bar_set_has_subtitle(
        header, bar->Has(DWW_TITLE_BAR_TITLE) && bar->Has(DWW_TITLE_BAR_HOST));
  } else {
    // Without a title of its own the header bar shows the window title.
    gtk_header_bar_set_custom_title(header, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  }
  gtk_widget_show_all(bar->header);
  gtk_window_set_titlebar(window, bar->header);
  TitleBars()[request->browser] = std::move(title_bar);
  return DWW_COMPOSE_HANDLED;
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  const auto found = TitleBars().find(state->browser);
  if (found == TitleBars().end()) return;
  TitleBar* bar = found->second.get();
  if (bar->back != nullptr) {
    gtk_widget_set_sensitive(bar->back, state->can_go_back);
    gtk_widget_set_sensitive(bar->forward, state->can_go_forward);
  }
  bar->loading = state->is_loading;
  if (bar->reload != nullptr) {
    gtk_button_set_image(
        GTK_BUTTON(bar->reload),
        gtk_image_new_from_icon_name(
            bar->loading ? "process-stop-symbolic" : "view-refresh-symbolic",
            GTK_ICON_SIZE_BUTTON));
  }
  const std::string title = state->title != nullptr && *state->title != '\0'
                                ? state->title
                                : bar->fallback_title;
  const std::string host = dww::HostOf(state->url);
  // The window title also names the window in the task switcher, so it
  // follows the page even when the title bar hides it.
  gtk_window_set_title(bar->window, title.c_str());
  GtkHeaderBar* header = GTK_HEADER_BAR(bar->header);
  if (bar->Has(DWW_TITLE_BAR_TITLE)) {
    gtk_header_bar_set_title(header, title.c_str());
    if (bar->Has(DWW_TITLE_BAR_HOST)) {
      gtk_header_bar_set_subtitle(header, host.empty() ? nullptr : host.c_str());
    }
  } else if (bar->Has(DWW_TITLE_BAR_HOST)) {
    gtk_header_bar_set_title(header, host.c_str());
  }
}

void Closing(void*, int64_t browser) {
  // The widgets are destroyed with the window.
  TitleBars().erase(browser);
}

}  // namespace

namespace dww {

const DWWComposer& DefaultComposer() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged,
                                    nullptr, Closing};
  return composer;
}

}  // namespace dww

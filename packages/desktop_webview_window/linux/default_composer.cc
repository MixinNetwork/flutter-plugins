// The default composer: an icon-only toolbar above the WebView. It uses only
// the public composer API.

#include <gtk/gtk.h>

#include <map>
#include <memory>

#include "composer_runtime.h"

namespace {

struct Toolbar {
  int64_t browser;
  GtkWidget* back;
  GtkWidget* forward;
  GtkWidget* reload;
  GtkWidget* reload_icon;
  GtkWidget* title;
  bool loading = false;
};

std::map<int64_t, std::unique_ptr<Toolbar>>& Toolbars() {
  static auto* toolbars = new std::map<int64_t, std::unique_ptr<Toolbar>>();
  return *toolbars;
}

GtkWidget* IconButton(const char* icon, Toolbar* toolbar,
                      void (*clicked)(GtkButton*, Toolbar*),
                      GtkWidget** image = nullptr) {
  GtkWidget* button = gtk_button_new();
  GtkWidget* content = gtk_image_new_from_icon_name(icon, GTK_ICON_SIZE_BUTTON);
  gtk_container_add(GTK_CONTAINER(button), content);
  gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(button, FALSE);
  g_signal_connect(button, "clicked", G_CALLBACK(clicked), toolbar);
  if (image != nullptr) *image = content;
  return button;
}

DWWComposeResult Compose(void*, const DWWComposeRequest* request) {
  auto* window = GTK_WINDOW(request->window);
  auto* webview = GTK_WIDGET(request->webview_view);
  if (!request->show_toolbar) {
    gtk_container_add(GTK_CONTAINER(window), webview);
    return DWW_COMPOSE_HANDLED;
  }
  auto toolbar = std::make_unique<Toolbar>();
  toolbar->browser = request->browser;
  GtkWidget* bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  gtk_container_set_border_width(GTK_CONTAINER(bar), 4);
  toolbar->back = IconButton("go-previous-symbolic", toolbar.get(),
                             +[](GtkButton*, Toolbar* t) {
                               dww_browser_go_back(t->browser);
                             });
  toolbar->forward = IconButton("go-next-symbolic", toolbar.get(),
                                +[](GtkButton*, Toolbar* t) {
                                  dww_browser_go_forward(t->browser);
                                });
  toolbar->reload = IconButton(
      "view-refresh-symbolic", toolbar.get(),
      +[](GtkButton*, Toolbar* t) {
        if (t->loading) {
          dww_browser_stop(t->browser);
        } else {
          dww_browser_reload(t->browser);
        }
      },
      &toolbar->reload_icon);
  toolbar->title = gtk_label_new(nullptr);
  gtk_label_set_ellipsize(GTK_LABEL(toolbar->title), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(toolbar->title), 0);
  gtk_widget_set_margin_start(toolbar->title, 8);
  gtk_widget_set_sensitive(toolbar->back, FALSE);
  gtk_widget_set_sensitive(toolbar->forward, FALSE);
  gtk_box_pack_start(GTK_BOX(bar), toolbar->back, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(bar), toolbar->forward, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(bar), toolbar->reload, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(bar), toolbar->title, TRUE, TRUE, 0);

  GtkWidget* column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_box_pack_start(GTK_BOX(column), bar, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(column), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL),
                     FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(column), webview, TRUE, TRUE, 0);
  gtk_container_add(GTK_CONTAINER(window), column);
  gtk_widget_show_all(column);
  Toolbars()[request->browser] = std::move(toolbar);
  return DWW_COMPOSE_HANDLED;
}

void NavigationChanged(void*, const DWWNavigationState* state) {
  const auto found = Toolbars().find(state->browser);
  if (found == Toolbars().end()) return;
  Toolbar* toolbar = found->second.get();
  gtk_widget_set_sensitive(toolbar->back, state->can_go_back);
  gtk_widget_set_sensitive(toolbar->forward, state->can_go_forward);
  toolbar->loading = state->is_loading;
  gtk_image_set_from_icon_name(
      GTK_IMAGE(toolbar->reload_icon),
      toolbar->loading ? "process-stop-symbolic" : "view-refresh-symbolic",
      GTK_ICON_SIZE_BUTTON);
  gtk_label_set_text(GTK_LABEL(toolbar->title),
                     state->title != nullptr ? state->title : "");
}

void Closing(void*, int64_t browser) {
  // The widgets are destroyed with the window.
  Toolbars().erase(browser);
}

}  // namespace

namespace dww {

const DWWComposer& DefaultComposer() {
  static const DWWComposer composer{nullptr, Compose, NavigationChanged,
                                    nullptr, Closing};
  return composer;
}

}  // namespace dww

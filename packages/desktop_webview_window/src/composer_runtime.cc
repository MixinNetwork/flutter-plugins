#include "composer_runtime.h"

#include <unordered_map>

namespace {

// Everything here runs on the platform main thread.
int64_t next_browser = 1;
bool has_app_composer = false;
DWWComposer app_composer{};
std::unordered_map<int64_t, dww::Browser*> browsers;

dww::Browser* Find(int64_t id) {
  const auto found = browsers.find(id);
  return found == browsers.end() ? nullptr : found->second;
}

}  // namespace

namespace dww {

int64_t NextBrowserId() { return next_browser++; }

void RegisterBrowser(int64_t id, Browser* browser) { browsers[id] = browser; }

void UnregisterBrowser(int64_t id) { browsers.erase(id); }

ComposerBinding::ComposerBinding() {
  if (has_app_composer) app_ = app_composer;
}

void ComposerBinding::Compose(const DWWComposeRequest& request) {
  Scope scope(depth_);
  if (app_.compose != nullptr &&
      app_.compose(app_.user, &request) == DWW_COMPOSE_HANDLED) {
    owner_ = app_;
    return;
  }
  owner_ = DefaultComposer();
  // A close requested by the application composer skips the default layout.
  if (!closing_) owner_.compose(owner_.user, &request);
}

void ComposerBinding::NavigationChanged(const DWWNavigationState& state) {
  if (closing_ || owner_.navigation_changed == nullptr) return;
  Scope scope(depth_);
  owner_.navigation_changed(owner_.user, &state);
}

bool ComposerBinding::Layout(int64_t browser, int32_t width, int32_t height) {
  if (owner_.layout == nullptr) return false;
  if (closing_) return true;
  Scope scope(depth_);
  owner_.layout(owner_.user, browser, width, height);
  return true;
}

void ComposerBinding::Closing(int64_t browser) {
  closing_ = true;
  if (closed_) return;
  closed_ = true;
  if (owner_.closing == nullptr) return;
  Scope scope(depth_);
  owner_.closing(owner_.user, browser);
}

}  // namespace dww

extern "C" {

void dww_set_composer(const DWWComposer* composer) {
  has_app_composer = composer != nullptr && composer->compose != nullptr;
  app_composer = has_app_composer ? *composer : DWWComposer{};
}

int32_t dww_browser_go_back(int64_t browser) {
  auto* found = Find(browser);
  return found != nullptr && found->GoBack();
}

int32_t dww_browser_go_forward(int64_t browser) {
  auto* found = Find(browser);
  return found != nullptr && found->GoForward();
}

int32_t dww_browser_reload(int64_t browser) {
  auto* found = Find(browser);
  return found != nullptr && found->Reload();
}

int32_t dww_browser_stop(int64_t browser) {
  auto* found = Find(browser);
  return found != nullptr && found->Stop();
}

int32_t dww_browser_close(int64_t browser) {
  auto* found = Find(browser);
  return found != nullptr && found->Close();
}

}  // extern "C"

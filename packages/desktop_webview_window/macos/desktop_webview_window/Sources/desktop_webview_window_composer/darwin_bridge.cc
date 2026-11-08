#include "include/dww_darwin.h"

#include <memory>
#include <unordered_map>

#include "../../../../src/composer_runtime.h"

namespace {

DWWComposer default_composer{};

class SwiftBrowser : public dww::Browser {
 public:
  explicit SwiftBrowser(const DWWDarwinBrowser& ops) : ops_(ops) {}
  bool GoBack() override { return ops_.go_back(ops_.target); }
  bool GoForward() override { return ops_.go_forward(ops_.target); }
  bool Reload() override { return ops_.reload(ops_.target); }
  bool Stop() override { return ops_.stop(ops_.target); }
  bool Close() override { return ops_.close(ops_.target); }

 private:
  DWWDarwinBrowser ops_;
};

std::unordered_map<int64_t, std::unique_ptr<SwiftBrowser>>& Browsers() {
  static auto* browsers =
      new std::unordered_map<int64_t, std::unique_ptr<SwiftBrowser>>();
  return *browsers;
}

}  // namespace

namespace dww {

const DWWComposer& DefaultComposer() { return default_composer; }

}  // namespace dww

struct DWWDarwinBinding {
  dww::ComposerBinding binding;
};

extern "C" {

int64_t dww_darwin_next_browser_id(void) { return dww::NextBrowserId(); }

void dww_darwin_register_browser(int64_t browser, const DWWDarwinBrowser* ops) {
  auto& entry = Browsers()[browser];
  entry = std::make_unique<SwiftBrowser>(*ops);
  dww::RegisterBrowser(browser, entry.get());
}

void dww_darwin_unregister_browser(int64_t browser) {
  dww::UnregisterBrowser(browser);
  Browsers().erase(browser);
}

void dww_darwin_set_default_composer(const DWWComposer* composer) {
  default_composer = *composer;
}

DWWDarwinBinding* dww_darwin_binding_new(void) { return new DWWDarwinBinding(); }

void dww_darwin_binding_free(DWWDarwinBinding* binding) { delete binding; }

void dww_darwin_binding_compose(DWWDarwinBinding* binding,
                                const DWWComposeRequest* request) {
  binding->binding.Compose(*request);
}

void dww_darwin_binding_navigation_changed(DWWDarwinBinding* binding,
                                           const DWWNavigationState* state) {
  binding->binding.NavigationChanged(*state);
}

void dww_darwin_binding_closing(DWWDarwinBinding* binding, int64_t browser) {
  binding->binding.Closing(browser);
}

void dww_darwin_binding_begin_close(DWWDarwinBinding* binding) {
  binding->binding.BeginClose();
}

int32_t dww_darwin_binding_dispatching(const DWWDarwinBinding* binding) {
  return binding->binding.dispatching();
}

}  // extern "C"

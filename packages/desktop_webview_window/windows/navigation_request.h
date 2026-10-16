#ifndef WEBVIEW_WINDOW_WINDOWS_NAVIGATION_REQUEST_H_
#define WEBVIEW_WINDOW_WINDOWS_NAVIGATION_REQUEST_H_

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace webview_window {

// NavigationStarting cannot be deferred. Share its asynchronous Dart decision
// with WebResourceRequested, which can defer the original HTTP request.
// All access takes place on the platform thread.
class NavigationRequest {
 public:
  NavigationRequest(std::wstring url, uint64_t id)
      : url(std::move(url)), id(id) {}

  const std::wstring url;
  const uint64_t id;

  bool IsHttp() const {
    return url.compare(0, 7, L"http://") == 0 ||
           url.compare(0, 8, L"https://") == 0;
  }

  bool MatchesResource(const std::wstring& resource_url) const {
    // Fragments are present in NavigationStarting but are not sent over HTTP.
    return url.substr(0, url.find(L'#')) ==
           resource_url.substr(0, resource_url.find(L'#'));
  }

  void Complete(bool allow) {
    if (decision_.has_value()) {
      return;
    }
    decision_ = allow;
    auto callbacks = std::move(callbacks_);
    for (const auto& callback : callbacks) {
      callback(allow);
    }
  }

  void OnDecision(std::function<void(bool)> callback) {
    if (decision_.has_value()) {
      callback(*decision_);
    } else {
      callbacks_.push_back(std::move(callback));
    }
  }

 private:
  std::optional<bool> decision_;
  std::vector<std::function<void(bool)>> callbacks_;
};

}  // namespace webview_window

#endif  // WEBVIEW_WINDOW_WINDOWS_NAVIGATION_REQUEST_H_

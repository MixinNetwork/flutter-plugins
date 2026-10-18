//
// Created by yangbin on 2021/11/12.
//

#include "web_view.h"

#include <tchar.h>
#include <windows.h>
#include <shobjidl.h>

#include <cassert>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "strconv.h"
#include "utils.h"

namespace webview_window {

// Runs a task posted by WebView::RunAsync.
constexpr UINT kRunTask = WM_APP + 1;

// The host window is the composer's webview_view. WebView2 follows its size.
static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                WPARAM const wparam,
                                LPARAM const lparam) noexcept {
  if (message == kRunTask) {
    std::unique_ptr<std::function<void()>> task(
        reinterpret_cast<std::function<void()>*>(lparam));
    (*task)();
    return 0;
  }
  if (message == WM_ERASEBKGND) {
    auto* web_view =
        reinterpret_cast<WebView*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (web_view) {
      RECT bounds;
      GetClientRect(window, &bounds);
      HBRUSH brush = CreateSolidBrush(web_view->HostBackgroundColor());
      FillRect(reinterpret_cast<HDC>(wparam), &bounds, brush);
      DeleteObject(brush);
      return 1;
    }
  }
  if (message == WM_SIZE) {
    auto* web_view =
        reinterpret_cast<WebView*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (web_view) web_view->UpdateBounds();
  }
  return DefWindowProc(window, message, wparam, lparam);
}

const auto kWebViewClassName = _T("web_view_window_web_view");

using namespace Microsoft::WRL;

WebView::WebView(EventSink emit, NavigationRequest request_navigation,
                 std::function<void()> state_changed, int64_t web_view_id,
                 std::wstring userDataFolder, bool deny_camera_and_microphone,
                 std::wstring javascript_bridge)
    : emit_(std::move(emit)),
      request_navigation_(std::move(request_navigation)),
      state_changed_(std::move(state_changed)),
      javascript_bridge_(std::move(javascript_bridge)),
      web_view_id_(web_view_id),
      user_data_folder_(std::move(userDataFolder)),
      deny_camera_and_microphone_(deny_camera_and_microphone) {
  RegisterWindowClass(kWebViewClassName, WndProc);
  // Hidden until the browser window has been composed.
  view_window_ = wil::unique_hwnd(::CreateWindowEx(
      0, kWebViewClassName, L"", WS_CHILD | WS_CLIPCHILDREN, 0, 0, 0, 0,
      HWND_MESSAGE, nullptr, ::GetModuleHandle(nullptr), nullptr));
  if (view_window_) {
    SetWindowLongPtr(view_window_.get(), GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));
  }
}

void WebView::NotifyStateChanged() {
  if (!closed_ && state_changed_) state_changed_();
}

WebView::NavigationState WebView::State() const {
  NavigationState state;
  state.can_go_back = CanGoBack();
  state.can_go_forward = CanGoForward();
  state.is_loading = loading_;
  if (webview_) {
    wil::unique_cotaskmem_string source;
    if (SUCCEEDED(webview_->get_Source(&source)) && source) {
      state.url = source.get();
      // A new WebView reports about:blank before its first navigation.
      if (state.url == L"about:blank") state.url.clear();
    }
    wil::unique_cotaskmem_string title;
    if (SUCCEEDED(webview_->get_DocumentTitle(&title)) && title) {
      state.title = title.get();
    }
  }
  return state;
}

void WebView::Create(std::function<void(HRESULT)> callback) {
  auto keep_alive = shared_from_this();
  on_web_view_created_callback_ = std::move(callback);
  if (closed_ || !view_window_) {
    CompleteCreation(E_FAIL);
    return;
  }
  // WebView2 completions may arrive after the native window has closed. Each
  // callback holds only a weak reference, and promotes it on the platform thread.
  auto weak = weak_from_this();
  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data_folder_.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [weak](HRESULT result, ICoreWebView2Environment *env) -> HRESULT {
            auto self = weak.lock();
            if (!self || self->closed_) {
              return S_OK;
            }
            if (FAILED(result) || !env) {
              self->CompleteCreation(FAILED(result) ? result : E_FAIL);
              return S_OK;
            }
            if (self->deny_camera_and_microphone_) {
              // SavesInProfile is available in Runtime 111 and later. Do not
              // silently turn a window-scoped policy into a persistent denial
              // on older runtimes.
              wil::unique_cotaskmem_string version;
              int comparison = 0;
              HRESULT hr = env->get_BrowserVersionString(&version);
              if (SUCCEEDED(hr)) {
                hr = CompareBrowserVersions(version.get(), L"111.0.1661.34",
                                            &comparison);
              }
              if (FAILED(hr) || comparison < 0) {
                self->CompleteCreation(
                    FAILED(hr) ? hr : HRESULT_FROM_WIN32(ERROR_OLD_WIN_VERSION));
                return S_OK;
              }
            }
            self->environment_ = env;
            auto completion =
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [weak](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                      auto self = weak.lock();
                      if (!self || self->closed_) {
                        if (controller) {
                          controller->Close();
                        }
                        return S_OK;
                      }
                      if (FAILED(result) || !controller) {
                        self->CompleteCreation(FAILED(result) ? result : E_FAIL);
                        return S_OK;
                      }
                      self->webview_controller_ = controller;
                      // Configure the browser before completing the Dart create.
                      self->CompleteCreation(self->OnWebviewControllerCreated());
                      return S_OK;
                    });
            // Newer runtimes accept the canvas color before creating any
            // compositor surface, avoiding even the initial white frame.
            wil::com_ptr<ICoreWebView2Environment10> environment;
            wil::com_ptr<ICoreWebView2ControllerOptions> options;
            wil::com_ptr<ICoreWebView2ControllerOptions3> color_options;
            HRESULT create_result;
            if (SUCCEEDED(env->QueryInterface(IID_PPV_ARGS(&environment))) &&
                SUCCEEDED(environment->CreateCoreWebView2ControllerOptions(&options)) &&
                SUCCEEDED(options->QueryInterface(IID_PPV_ARGS(&color_options)))) {
              COLORREF color = self->background_color_;
              color_options->put_DefaultBackgroundColor(
                  {255, GetRValue(color), GetGValue(color), GetBValue(color)});
              create_result = environment->CreateCoreWebView2ControllerWithOptions(
                  self->view_window_.get(), options.get(), completion.Get());
            } else {
              create_result = env->CreateCoreWebView2Controller(
                  self->view_window_.get(), completion.Get());
            }
            if (FAILED(create_result)) {
              self->CompleteCreation(create_result);
            }
            return S_OK;
          }).Get());
  if (FAILED(hr)) {
    CompleteCreation(hr);
  }
}

void WebView::Emit(const std::string &method, flutter::EncodableMap args) {
  if (closed_ || !emit_) return;
  args[flutter::EncodableValue("id")] = flutter::EncodableValue(web_view_id_);
  emit_(method, std::move(args));
}

void WebView::CompleteCreation(HRESULT result) {
  auto callback = std::exchange(on_web_view_created_callback_, nullptr);
  if (callback) {
    callback(result);
  }
}

HRESULT WebView::OnWebviewControllerCreated() {
  if (!webview_controller_) {
    return E_POINTER;
  }
  SetBackgroundColor(background_color_);
  
  HRESULT hr = webview_controller_->get_CoreWebView2(&webview_);
  if (FAILED(hr) || !webview_) {
    std::cerr << "failed to get core webview" << std::endl;
    return FAILED(hr) ? hr : E_FAIL;
  }

  wil::com_ptr<ICoreWebView2Settings> settings;
  ApplyPreferredColorScheme();
  hr = webview_->get_Settings(&settings);
  if (FAILED(hr) || !settings) {
    std::cerr << "failed to get settings" << std::endl;
    return FAILED(hr) ? hr : E_FAIL;
  }
  
  settings->put_IsScriptEnabled(true);
  settings->put_IsZoomControlEnabled(false);
  // The page's own context menu, as on macOS and Linux. DevTools, and with
  // them the menu's Inspect item, stay off until openDevToolsWindow.
  settings->put_AreDevToolsEnabled(FALSE);
  settings->put_IsStatusBarEnabled(false);
  settings->put_IsWebMessageEnabled(true);

  wil::com_ptr<ICoreWebView2Settings2> settings2;
  hr = settings->QueryInterface(IID_PPV_ARGS(&settings2));
  if (SUCCEEDED(hr) && settings2) {
    wil::unique_cotaskmem_string user_agent;
    hr = settings2->get_UserAgent(&user_agent);
    if (SUCCEEDED(hr) && user_agent) {
      default_user_agent_ = std::wstring(user_agent.get());
    }
  }

  webview_controller_->put_IsVisible(visible_);
  UpdateBounds();

  if (!javascript_bridge_.empty()) {
    // Registered before the first navigation, so every page gets the bridge.
    hr = webview_->AddScriptToExecuteOnDocumentCreated(
        javascript_bridge_.c_str(), nullptr);
    if (FAILED(hr)) return hr;
  }

  // Always use single window to load web page.
  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2 *sender,
             ICoreWebView2NewWindowRequestedEventArgs *args) {
            wil::unique_cotaskmem_string url;
            HRESULT hr = args->get_Uri(&url);
            if (SUCCEEDED(hr) && url) {
              sender->Navigate(url.get());
            }
            args->put_Handled(true);
            return S_OK;
          })
          .Get(),
      nullptr);

  wil::com_ptr<ICoreWebView2_4> webview4;
  if (SUCCEEDED(webview_->QueryInterface(IID_PPV_ARGS(&webview4)))) {
    // Downloads ask where to save, as on macOS and Linux. WebView2 keeps its
    // download progress flyout.
    webview4->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [weak = weak_from_this()](
                ICoreWebView2 *sender,
                ICoreWebView2DownloadStartingEventArgs *args) {
              auto self = weak.lock();
              if (!self || self->closed_) return args->put_Cancel(TRUE);
              wil::com_ptr<ICoreWebView2Deferral> deferral;
              HRESULT hr = args->GetDeferral(&deferral);
              if (FAILED(hr)) return hr;
              // A modal dialog must not run inside a WebView2 event handler.
              self->RunAsync([weak, args = wil::com_ptr<
                                        ICoreWebView2DownloadStartingEventArgs>(args),
                              deferral] {
                auto self = weak.lock();
                if (self && !self->closed_) {
                  self->ChooseDownloadPath(args.get());
                } else {
                  args->put_Cancel(TRUE);
                }
                deferral->Complete();
              });
              return S_OK;
            })
            .Get(),
        nullptr);
  }

  if (deny_camera_and_microphone_) {
    // Answered here, so the request never reaches Windows' own privacy prompt.
    hr = webview_->add_PermissionRequested(
        Callback<ICoreWebView2PermissionRequestedEventHandler>(
            [](ICoreWebView2 *sender,
               ICoreWebView2PermissionRequestedEventArgs *args) {
              COREWEBVIEW2_PERMISSION_KIND kind;
              if (SUCCEEDED(args->get_PermissionKind(&kind)) &&
                  (kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA ||
                   kind == COREWEBVIEW2_PERMISSION_KIND_MICROPHONE)) {
                wil::com_ptr<ICoreWebView2PermissionRequestedEventArgs3> args3;
                HRESULT hr = args->QueryInterface(IID_PPV_ARGS(&args3));
                if (FAILED(hr)) return hr;
                hr = args3->put_SavesInProfile(FALSE);
                if (FAILED(hr)) return hr;
                return args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
              }
              return S_OK;
            })
            .Get(),
        nullptr);
    if (FAILED(hr)) return hr;
  }

  webview_->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [](ICoreWebView2 *sender,
             ICoreWebView2ContentLoadingEventArgs *args) { return S_OK; })
          .Get(),
      nullptr);

  webview_->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *sender, IUnknown *args) {
            auto self = weak.lock();
            if (self) self->NotifyStateChanged();
            return S_OK;
          })
          .Get(),
      nullptr);
  webview_->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *,
                                    ICoreWebView2SourceChangedEventArgs *) {
            auto self = weak.lock();
            if (self) self->NotifyStateChanged();
            return S_OK;
          })
          .Get(),
      nullptr);
  webview_->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *, IUnknown *) {
            auto self = weak.lock();
            if (self) self->NotifyStateChanged();
            return S_OK;
          })
          .Get(),
      nullptr);

  // ContentLoading identifies a document that has committed, unlike a
  // navigation that was cancelled before replacing the initial empty page.
  webview_->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *,
                                   ICoreWebView2ContentLoadingEventArgs *args) {
            auto self = weak.lock();
            if (!self || self->closed_ || !self->startup_background_) return S_OK;
            UINT64 navigation_id;
            if (SUCCEEDED(args->get_NavigationId(&navigation_id))) {
              self->startup_navigation_id_ = navigation_id;
            }
            return S_OK;
          }).Get(), nullptr);
  // NavigationStarting only reports top-level navigations, including redirects.
  // It has no deferral, so Dart decides synchronously before the handler
  // returns; an allowed navigation keeps its method, body and headers.
  webview_->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *sender,
                 ICoreWebView2NavigationStartingEventArgs *args) {
            auto self = weak.lock();
            if (!self || self->closed_) return S_OK;
            self->declined_url_.clear();
            self->loading_ = true;
            self->NotifyStateChanged();
            if (!self->triggerOnUrlRequestedEvent) {
              // Only the explicitly launched navigation bypasses Dart.
              self->triggerOnUrlRequestedEvent = true;
              return S_OK;
            }
            if (!self->url_request_enabled_ || !self->request_navigation_) {
              return S_OK;
            }
            wil::unique_cotaskmem_string uri;
            if (FAILED(args->get_Uri(&uri)) || !uri) {
              args->put_Cancel(true);
              return S_OK;
            }
            std::wstring url(uri.get());
            if (!self->request_navigation_(url)) {
              self->declined_url_ = url.substr(0, url.find(L'#'));
              args->put_Cancel(true);
            }
            return S_OK;
          })
          .Get(),
      nullptr);
  webview_->AddWebResourceRequestedFilter(
      L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT);
  webview_->add_WebResourceRequested(
      Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *sender,
                  ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
            auto self = weak.lock();
            if (!self || self->closed_ || self->declined_url_.empty()) {
              return S_OK;
            }
            wil::com_ptr<ICoreWebView2WebResourceRequest> request;
            wil::unique_cotaskmem_string uri;
            if (FAILED(args->get_Request(&request)) || !request ||
                FAILED(request->get_Uri(&uri)) || !uri) {
              return S_OK;
            }
            std::wstring url(uri.get());
            if (url.substr(0, url.find(L'#')) != self->declined_url_) {
              return S_OK;
            }
            self->declined_url_.clear();
            // A synthetic 204 keeps the request off the network and leaves the
            // current document in place, like the cancelled navigation.
            wil::com_ptr<ICoreWebView2WebResourceResponse> response;
            if (SUCCEEDED(self->environment_->CreateWebResourceResponse(
                    nullptr, 204, L"No Content", L"", &response))) {
              args->put_Response(response.get());
            }
            return S_OK;
          })
          .Get(),
      nullptr);
  webview_->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *,
                 ICoreWebView2NavigationCompletedEventArgs *args) {
            auto self = weak.lock();
            if (!self || self->closed_) return S_OK;
            UINT64 navigation_id = 0;
            // Restore only a committed document, including about:blank and
            // a document whose subresources the user stopped loading.
            if (self->startup_background_ &&
                SUCCEEDED(args->get_NavigationId(&navigation_id)) &&
                self->startup_navigation_id_ == navigation_id) {
              self->startup_background_ = false;
              self->SetBackgroundColor(RGB(255, 255, 255));
            }
            self->loading_ = false;
            self->NotifyStateChanged();
            return S_OK;
          })
          .Get(),
      nullptr);
  webview_->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [weak = weak_from_this()](ICoreWebView2 *sender,
                 ICoreWebView2WebMessageReceivedEventArgs *args) {
            auto self = weak.lock();
            if (!self || self->closed_) return S_OK;
            // The injected bridge always posts a JSON string; anything else
            // did not come from window.desktopWebview.
            wil::unique_cotaskmem_string message;
            if (FAILED(args->TryGetWebMessageAsString(&message)) || !message) {
              return S_OK;
            }
            self->Emit("onJavaScriptMessage", flutter::EncodableMap{
                {flutter::EncodableValue("message"),
                 flutter::EncodableValue(wide_to_utf8(std::wstring(message.get())))},
            });
            return S_OK;
          })
          .Get(),
      nullptr);
  return S_OK;
}

void WebView::UpdateBounds() {
  // Resize WebView to fit the bounds of the parent window
  RECT bounds;
  GetClientRect(view_window_.get(), &bounds);
  if (webview_controller_) 
    webview_controller_->put_Bounds(bounds);
}

void WebView::Navigate(const std::wstring &url) {
  if (webview_) {
    webview_->Navigate(url.c_str());
  } else {
    std::cerr << "webview not created" << std::endl;
  }
}

void WebView::SetBackgroundColor(COLORREF color) {
  background_color_ = color;
  if (webview_controller_) {
    wil::com_ptr<ICoreWebView2Controller2> controller;
    if (SUCCEEDED(webview_controller_->QueryInterface(IID_PPV_ARGS(&controller)))) {
      controller->put_DefaultBackgroundColor(
          {255, GetRValue(color), GetGValue(color), GetBValue(color)});
    }
  }
}

void WebView::SetBrightness(int brightness, bool dark) {
  brightness_ = brightness;
  host_background_color_ = ContentBackgroundColor(dark);
  if (view_window_) InvalidateRect(view_window_.get(), nullptr, TRUE);
  if (startup_background_) SetBackgroundColor(host_background_color_);
  ApplyPreferredColorScheme();
}

void WebView::ApplyPreferredColorScheme() {
  if (!webview_) return;
  // PreferredColorScheme belongs to the shared profile. Emulate only this
  // WebView's media feature so windows can keep independent appearances.
  const wchar_t* parameters = brightness_ < 0 ? LR"({"features":[]})"
      : brightness_ == 0
          ? LR"({"features":[{"name":"prefers-color-scheme","value":"dark"}]})"
          : LR"({"features":[{"name":"prefers-color-scheme","value":"light"}]})";
  webview_->CallDevToolsProtocolMethod(L"Emulation.setEmulatedMedia", parameters,
      Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
          [](HRESULT, LPCWSTR) { return S_OK; }).Get());
}

void WebView::SetVisible(bool visible) {
  visible_ = visible;
  if (webview_controller_) {
    webview_controller_->put_IsVisible(visible);
  }
}

void WebView::Focus() {
  if (webview_controller_) {
    webview_controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
  }
}

void WebView::AddScriptToExecuteOnDocumentCreated(
    const std::wstring &javaScript) {
  if (webview_) {
    webview_->AddScriptToExecuteOnDocumentCreated(javaScript.c_str(), nullptr);
  }
}

void WebView::SetApplicationNameForUserAgent(const std::wstring &name) {
  if (webview_) {
    wil::com_ptr<ICoreWebView2Settings> settings;
    HRESULT hr = webview_->get_Settings(&settings);
    if (FAILED(hr) || !settings) {
      return;
    }
    wil::com_ptr<ICoreWebView2Settings2> settings2;
    hr = settings->QueryInterface(IID_PPV_ARGS(&settings2));
    if (SUCCEEDED(hr) && settings2) {
      settings2->put_UserAgent((default_user_agent_ + name).c_str());
    }
  }
}

void WebView::GoBack() {
  if (webview_) {
    webview_->GoBack();
  }
}

void WebView::GoForward() {
  if (webview_) {
    webview_->GoForward();
  }
}

void WebView::Reload() {
  if (webview_) {
    webview_->Reload();
  }
}

void WebView::Stop() {
  if (webview_) {
    webview_->Stop();
  }
}

void WebView::GetAllCookies(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (webview_) {
    wil::com_ptr<ICoreWebView2_2> webView2;
    HRESULT hr = webview_->QueryInterface(IID_PPV_ARGS(&webView2));

    if (FAILED(hr) || !webView2) {
      result->Error("0", "Failed to get ICoreWebView2_2");
      return;
    }

    wil::com_ptr<ICoreWebView2CookieManager> cookieManager;
    HRESULT hrc = webView2->get_CookieManager(&cookieManager);

    if (FAILED(hrc) || !cookieManager) {
      result->Error("0", "Failed to get ICoreWebView2CookieManager");
      return;
    }

    cookieManager->GetCookies(
        nullptr,
        Callback<ICoreWebView2GetCookiesCompletedHandler>(
            [result = std::move(result)](
                HRESULT hr, ICoreWebView2CookieList *cookieList) -> HRESULT {
              if (FAILED(hr) || !cookieList) {
                result->Error("0", "Failed to get cookies");
                return S_OK;
              }

              UINT cookieCount;
              hr = cookieList->get_Count(&cookieCount);
              if (FAILED(hr)) {
                result->Error("0", "Failed to get cookie count");
                return S_OK;
              }

              std::vector<flutter::EncodableValue> cookies;
              for (UINT i = 0; i < cookieCount; ++i) {
                wil::com_ptr<ICoreWebView2Cookie> cookie;
                hr = cookieList->GetValueAtIndex(i, &cookie);
                if (FAILED(hr) || !cookie) {
                  continue;
                }

                wil::unique_cotaskmem_string name;
                wil::unique_cotaskmem_string value;
                wil::unique_cotaskmem_string domain;
                wil::unique_cotaskmem_string path;
                double expires;
                BOOL isSecure;
                BOOL isHttpOnly;
                BOOL isSessionOnly;

                hr = cookie->get_Name(&name);
                if (FAILED(hr)) continue;
                hr = cookie->get_Value(&value);
                if (FAILED(hr)) continue;
                hr = cookie->get_Domain(&domain);
                if (FAILED(hr)) continue;
                hr = cookie->get_Path(&path);
                if (FAILED(hr)) continue;
                hr = cookie->get_Expires(&expires);
                if (FAILED(hr)) continue;
                hr = cookie->get_IsSecure(&isSecure);
                if (FAILED(hr)) continue;
                hr = cookie->get_IsHttpOnly(&isHttpOnly);
                if (FAILED(hr)) continue;
                hr = cookie->get_IsSession(&isSessionOnly);
                if (FAILED(hr)) continue;

                std::map<flutter::EncodableValue, flutter::EncodableValue>
                    cookieMap;
                cookieMap[flutter::EncodableValue("name")] =
                    flutter::EncodableValue(
                        webview_window::ConvertLPCWSTRToString(name.get()));
                cookieMap[flutter::EncodableValue("value")] =
                    flutter::EncodableValue(
                        webview_window::ConvertLPCWSTRToString(value.get()));
                cookieMap[flutter::EncodableValue("domain")] =
                    flutter::EncodableValue(
                        webview_window::ConvertLPCWSTRToString(domain.get()));
                cookieMap[flutter::EncodableValue("path")] =
                    flutter::EncodableValue(
                        webview_window::ConvertLPCWSTRToString(path.get()));

                if (expires >= 0) {
                  cookieMap[flutter::EncodableValue(std::string("expires"))] =
                      flutter::EncodableValue(static_cast<double>(expires));
                } else {
                  cookieMap[flutter::EncodableValue(std::string("expires"))] =
                      flutter::EncodableValue();
                }

                cookieMap[flutter::EncodableValue("secure")] =
                    flutter::EncodableValue(static_cast<bool>(isSecure));
                cookieMap[flutter::EncodableValue("httpOnly")] =
                    flutter::EncodableValue(static_cast<bool>(isHttpOnly));
                cookieMap[flutter::EncodableValue("sessionOnly")] =
                    flutter::EncodableValue(static_cast<bool>(isSessionOnly));

                cookies.push_back(flutter::EncodableValue(cookieMap));
              }

              result->Success(flutter::EncodableValue(cookies));
              return S_OK;
            })
            .Get());

  } else {
    result->Error("0", "webview not created");
  }
}

void WebView::openDevToolsWindow() {
  if (!webview_) return;
  wil::com_ptr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(webview_->get_Settings(&settings)) && settings) {
    settings->put_AreDevToolsEnabled(TRUE);
  }
  webview_->OpenDevToolsWindow();
}

bool WebView::CanGoBack() const {
  if (webview_) {
    BOOL can_go_back;
    webview_->get_CanGoBack(&can_go_back);
    return can_go_back;
  }
  return false;
}

bool WebView::CanGoForward() const {
  if (webview_) {
    BOOL can_go_forward;
    webview_->get_CanGoForward(&can_go_forward);
    return can_go_forward;
  }
  return false;
}

void WebView::ExecuteJavaScript(
    const std::wstring &javaScript,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer) {
  if (webview_) {
    webview_->ExecuteScript(
        javaScript.c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [completer(std::move(completer))](HRESULT error,
                                              PCWSTR result) -> HRESULT {
              if (error != S_OK) {
                completer->Error("0", "Error executing JavaScript");
              } else {
                // ExecuteScript already returns JSON ("null" for undefined).
                if (result) {
                  completer->Success(flutter::EncodableValue(
                      wide_to_utf8(std::wstring(result))));
                } else {
                  completer->Success();
                }
              }
              return S_OK;
            })
            .Get());
  } else {
    completer->Error("0", "webview not created");
  }
}

void WebView::PostJavaScriptMessage(
    const std::wstring &message,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> completer) {
  if (!webview_) {
    completer->Error("browser_not_ready", "The browser view is not ready.");
    return;
  }
  if (FAILED(webview_->PostWebMessageAsString(message.c_str()))) {
    completer->Error("post_message_failed", "Failed to post the message.");
    return;
  }
  completer->Success();
}

void WebView::setTriggerOnUrlRequestedEvent(const bool value) {
  this->triggerOnUrlRequestedEvent = value;
}

void WebView::RunAsync(std::function<void()> task) {
  auto *posted = new std::function<void()>(std::move(task));
  if (!view_window_ ||
      !PostMessage(view_window_.get(), kRunTask, 0,
                   reinterpret_cast<LPARAM>(posted))) {
    (*posted)();
    delete posted;
  }
}

void WebView::ChooseDownloadPath(ICoreWebView2DownloadStartingEventArgs *args) {
  // WebView2 proposes a path in the default download folder.
  wil::unique_cotaskmem_string proposed;
  args->get_ResultFilePath(&proposed);
  std::wstring path = proposed ? proposed.get() : L"";
  auto separator = path.find_last_of(L"\\/");
  std::wstring folder =
      separator == std::wstring::npos ? L"" : path.substr(0, separator);
  std::wstring name =
      separator == std::wstring::npos ? path : path.substr(separator + 1);

  auto dialog = wil::CoCreateInstanceNoThrow<IFileSaveDialog>(CLSID_FileSaveDialog);
  if (!dialog) {
    args->put_Cancel(TRUE);
    return;
  }
  wil::com_ptr<IShellItem> folder_item;
  if (!folder.empty() &&
      SUCCEEDED(SHCreateItemFromParsingName(folder.c_str(), nullptr,
                                            IID_PPV_ARGS(&folder_item)))) {
    dialog->SetFolder(folder_item.get());
  }
  dialog->SetFileName(name.c_str());
  auto dot = name.find_last_of(L'.');
  if (dot != std::wstring::npos) {
    dialog->SetDefaultExtension(name.substr(dot + 1).c_str());
  }

  HWND owner = view_window_ ? GetAncestor(view_window_.get(), GA_ROOT) : nullptr;
  wil::com_ptr<IShellItem> result;
  wil::unique_cotaskmem_string chosen;
  if (SUCCEEDED(dialog->Show(owner)) && SUCCEEDED(dialog->GetResult(&result)) &&
      SUCCEEDED(result->GetDisplayName(SIGDN_FILESYSPATH, &chosen)) &&
      !closed_) {
    args->put_ResultFilePath(chosen.get());
  } else {
    args->put_Cancel(TRUE);
  }
}

void WebView::Close() {
  if (closed_) {
    return;
  }
  closed_ = true;
  // The window resolves its pending create result; abandon the backend callback.
  on_web_view_created_callback_ = nullptr;
  state_changed_ = nullptr;
  if (view_window_) {
    SetWindowLongPtr(view_window_.get(), GWLP_USERDATA, 0);
  }
  if (webview_) {
    webview_->Stop();
  }
  if (webview_controller_) {
    webview_controller_->Close();
  }
  webview_.reset();
  webview_controller_.reset();
  view_window_.reset();
}

WebView::~WebView() {
  Close();
}

}  // namespace webview_window

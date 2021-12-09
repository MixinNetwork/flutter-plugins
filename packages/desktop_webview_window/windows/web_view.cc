//
// Created by yangbin on 2021/11/12.
//

#include <windows.h>
#include <tchar.h>
#include <cassert>
#include <iostream>
#include <utility>

#include "web_view.h"
#include "utils.h"

namespace webview_window {

static LRESULT CALLBACK WndProc(HWND const window,
                                UINT const message,
                                WPARAM const wparam,
                                LPARAM const lparam) noexcept {
  return DefWindowProc(window, message, wparam, lparam);
}

const auto kWebViewClassName = _T("web_view_window_web_view");

using namespace Microsoft::WRL;

WebView::WebView(
    std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel,
    int64_t web_view_id, std::wstring userDataFolder,
    std::function<void(HRESULT)> on_web_view_created
) : method_channel_(std::move(method_channel)),
    web_view_id_(web_view_id), user_data_folder_(std::move(userDataFolder)),
    on_web_view_created_callback_(std::move(on_web_view_created)) {
  RegisterWindowClass(kWebViewClassName, WndProc);
  view_window_ = wil::unique_hwnd(::CreateWindowEx(
      0,
      kWebViewClassName,
      L"",
      WS_CHILD | WS_VISIBLE,
      0,
      0,
      0,
      0,
      HWND_MESSAGE,
      nullptr,
      ::GetModuleHandle(nullptr),
      nullptr));
  assert(view_window_ != nullptr);
  if (!view_window_) {
    on_web_view_created_callback_(S_FALSE);
    return;
  }

  CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data_folder_.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this](HRESULT result, ICoreWebView2Environment *env) -> HRESULT {
            if (!SUCCEEDED(result)) {
              on_web_view_created_callback_(result);
              return S_OK;
            }
            env->CreateCoreWebView2Controller(
                view_window_.get(),
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                      on_web_view_created_callback_(result);
                      if (SUCCEEDED(result)) {
                        webview_controller_ = controller;
                        OnWebviewControllerCreated();
                      }
                      return S_OK;
                    }).Get());
            return S_OK;
          }).Get());

}

void WebView::OnWebviewControllerCreated() {
  if (!webview_controller_) {
    return;
  }
  webview_controller_->get_CoreWebView2(&webview_);

  if (!webview_) {
    std::cerr << "failed to get core webview" << std::endl;
    return;
  }

  ICoreWebView2Settings *settings;
  webview_->get_Settings(&settings);
  settings->put_IsScriptEnabled(true);
  settings->put_IsZoomControlEnabled(false);
  settings->put_AreDefaultContextMenusEnabled(false);
  settings->put_IsStatusBarEnabled(false);

  ICoreWebView2Settings2 *settings2;
  auto hr = settings->QueryInterface(IID_PPV_ARGS(&settings2));
  if (SUCCEEDED(hr)) {
    LPWSTR user_agent[256];
    settings2->get_UserAgent(user_agent);
    default_user_agent_ = std::wstring(*user_agent);
  }

  UpdateBounds();

  // Always use single window to load web page.
  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2 *sender, ICoreWebView2NewWindowRequestedEventArgs *args) {
            LPWSTR url;
            args->get_Uri(&url);
            sender->Navigate(url);
            args->put_Handled(true);
            return S_OK;
          }).Get(), nullptr);

  webview_->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [](ICoreWebView2 *sender, ICoreWebView2ContentLoadingEventArgs *args) {
            return S_OK;
          }).Get(), nullptr);

  webview_->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) {
            auto method_args = flutter::EncodableMap{
                {flutter::EncodableValue("id"), flutter::EncodableValue(web_view_id_)},
                {flutter::EncodableValue("canGoBack"), flutter::EncodableValue(CanGoBack())},
                {flutter::EncodableValue("canGoForward"), flutter::EncodableValue(CanGoForward())},
            };
            method_channel_->InvokeMethod("onHistoryChanged",
                                          std::make_unique<flutter::EncodableValue>(method_args));
            return S_OK;
          }
      ).Get(), nullptr);

  webview_->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this](ICoreWebView2 *sender, ICoreWebView2NavigationStartingEventArgs *args) {
            auto method_args = flutter::EncodableMap{
                {flutter::EncodableValue("id"), flutter::EncodableValue(web_view_id_)},
            };
            method_channel_->InvokeMethod("onNavigationStarted",
                                          std::make_unique<flutter::EncodableValue>(method_args));
            return S_OK;
          }
      ).Get(), nullptr);
  webview_->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this](ICoreWebView2 *sender, ICoreWebView2NavigationCompletedEventArgs *args) {
            auto method_args = flutter::EncodableMap{
                {flutter::EncodableValue("id"), flutter::EncodableValue(web_view_id_)},
            };
            method_channel_->InvokeMethod("onNavigationCompleted",
                                          std::make_unique<flutter::EncodableValue>(method_args));
            return S_OK;
          }
      ).Get(), nullptr);

//  webview_->add_WebMessageReceived(
//      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
//          [](ICoreWebView2 *webview, ICoreWebView2WebMessageReceivedEventArgs *args) {
//            PWSTR message;
//
//            args->TryGetWebMessageAsString(&message);
//            std::wstring str(message);
//            std::cout << "message: " << wide_to_utf8(str) << std::endl;
//            CoTaskMemFree(message);
//            return S_OK;
//          }
//      ).Get(), nullptr);

}

void WebView::UpdateBounds() {
  // Resize WebView to fit the bounds of the parent window
  RECT bounds;
  GetClientRect(view_window_.get(), &bounds);
  webview_controller_->put_Bounds(bounds);
}

void WebView::Navigate(const std::wstring &url) {
  if (webview_) {
    webview_->Navigate(url.c_str());
  } else {
    std::cerr << "webview not created" << std::endl;
  }
}

void WebView::AddScriptToExecuteOnDocumentCreated(const std::wstring &javaScript) {
  if (webview_) {
    webview_->AddScriptToExecuteOnDocumentCreated(javaScript.c_str(), nullptr);
  }
}

void WebView::SetApplicationNameForUserAgent(const std::wstring &name) {
  if (webview_) {
    ICoreWebView2Settings *settings;
    webview_->get_Settings(&settings);
    ICoreWebView2Settings2 *settings2;
    auto hr = settings->QueryInterface(IID_PPV_ARGS(&settings2));
    if (SUCCEEDED(hr)) {
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

WebView::~WebView() {
  if (webview_) {
    webview_->Stop();
  }
  if (webview_controller_) {
    webview_controller_->Close();
  }
}

}
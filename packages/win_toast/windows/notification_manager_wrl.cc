//
// Created by yangbin on 2022/12/6.
//

#ifdef WIN_TOAST_ENABLE_WRL

#include "Windows.h"
#include "notification_manager_wrl.h"

#include <wrl.h>
#include <windows.ui.notifications.h>
#include <NotificationActivationCallback.h>
#include "DesktopNotificationManagerCompat2.h"

#include <string>
#include <exception>

#pragma comment(lib, "shlwapi")
#pragma comment(lib, "user32")
#pragma comment(lib, "runtimeobject")

using namespace ABI::Windows::Data::Xml::Dom;
using namespace ABI::Windows::UI::Notifications;
using namespace ABI::Windows::Foundation;
using namespace Microsoft::WRL;

// The GUID must be unique to your app. Create a new GUID if copying this code.
class DECLSPEC_UUID("936C39FC-6BBC-4A57-B8F8-7C627E401B2F") NotificationActivator WrlSealed WrlFinal
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>, INotificationActivationCallback> {
 public:
  virtual HRESULT STDMETHODCALLTYPE Activate(
      _In_ LPCWSTR appUserModelId,
      _In_ LPCWSTR invokedArgs,
      _In_reads_(dataCount) const NOTIFICATION_USER_INPUT_DATA *data,
      ULONG dataCount) override {
    std::wstring arguments(invokedArgs);
    HRESULT hr = S_OK;

    if (FAILED(hr)) {
// Log failed HRESULT
    }

    return S_OK;
  }

  ~NotificationActivator() {
  }
};

// Flag class as COM creatable
CoCreatableClass(NotificationActivator);

#define RETURN_IF_FAILED(hr) do { HRESULT _hrTemp = hr; if (FAILED(_hrTemp)) { return _hrTemp; } } while (false)


void NotificationManagerWrl::Register(std::wstring aumId, std::wstring displayName, std::wstring icon_path) {
  DesktopNotificationManagerCompat::RegisterActivator();
}

HRESULT NotificationManagerWrl::ShowToast(
    std::wstring xml,
    std::wstring tag,
    std::wstring group,
    int64_t expiration_time
) {

  HRESULT hr;

  ComPtr<IXmlDocument> doc;
  hr = DesktopNotificationManagerCompat::CreateXmlDocumentFromString(xml.c_str(), &doc);
  if (SUCCEEDED(hr)) {
    ComPtr<IToastNotifier> notifier;
    hr = DesktopNotificationManagerCompat::CreateToastNotifier(&notifier);
    if (SUCCEEDED(hr)) {
      ComPtr<IToastNotification> toast;
      hr = DesktopNotificationManagerCompat::CreateToastNotification(doc.Get(), &toast);
      if (SUCCEEDED(hr)) {
        EventRegistrationToken activatedToken, dismissedToken, failedToken;
        hr = toast->add_Dismissed(
            Callback<Implements<RuntimeClassFlags<ClassicCom>,
                                ITypedEventHandler<ToastNotification *, ToastDismissedEventArgs * >>>(
                [this, tag, group](
                    IToastNotification *sender,
                    IToastDismissedEventArgs *args) -> HRESULT {
                  if (!dismissed_callback_) {
                    return S_OK;
                  }
                  ToastDismissalReason reason;
                  args->get_Reason(&reason);
                  dismissed_callback_(tag, group, reason);
                  return S_OK;
                }).Get(),
            &dismissedToken);
        hr = notifier->Show(toast.Get());
      }
    }
  }
  return hr;
}

void NotificationManagerWrl::Clear() {
  std::unique_ptr<DesktopNotificationHistoryCompat> history;
  auto hr = DesktopNotificationManagerCompat::get_History(&history);
  if (SUCCEEDED(hr)) {
    // Clear all toasts
    hr = history->Clear();
  }
}

void NotificationManagerWrl::Remove(std::wstring tag, std::wstring group) {
  std::unique_ptr<DesktopNotificationHistoryCompat> history;
  auto hr = DesktopNotificationManagerCompat::get_History(&history);
  if (SUCCEEDED(hr)) {
    hr = history->RemoveGroupedTag(tag.c_str(), group.c_str());
  }
}

#endif // WIN_TOAST_ENABLE_WRL
//
// Created by yangbin on 2022/12/6.
//

#ifdef WIN_TOAST_ENABLE_WRL

#include "pch.h"

#include "Windows.h"
#include "notification_manager_wrl.h"

#include "wrl_compat.h"
#include <windows.ui.notifications.h>
#include "DesktopNotificationManagerCompat2.h"
#include "dll_importer.h"

#include <string>
#include <exception>
#include <iostream>

#include "NotificationActivationCallback.h"
#include "wrl/module.h"

#pragma comment(lib, "runtimeobject.lib")

using namespace ABI::Windows::Data::Xml::Dom;
using namespace ABI::Windows::UI::Notifications;
using namespace ABI::Windows::Foundation;
using namespace Microsoft::WRL;

static DWORD cookies_[1] = {0};

class DECLSPEC_UUID(WIN_TOAST_WRL_ACTIVATOR_CLSID) NotificationActivator : public RuntimeClass<
    RuntimeClassFlags<ClassicCom>,
    INotificationActivationCallback> {
 public:

  static HRESULT Register() {
    auto &module = Module<OutOfProc>::Create();

    unsigned int flags = ModuleType::OutOfProcDisableCaching;

    ComPtr<IUnknown> factory;
    HRESULT hr = Details::CreateClassFactory<SimpleClassFactory<NotificationActivator>>(
        &flags, nullptr, __uuidof(IClassFactory), &factory);
    RETURN_IF_FAILED(hr);

    ComPtr<IClassFactory> factory_factory;
    hr = factory.As(&factory_factory);
    RETURN_IF_FAILED(hr);

    IClassFactory *class_factories[] = {factory_factory.Get()};
    IID class_ids[] = {__uuidof(NotificationActivator)};

    hr = module.RegisterCOMObject(nullptr, class_ids, class_factories,
                                  cookies_, std::extent<decltype(cookies_)>());
    RETURN_IF_FAILED(hr);

    return S_OK;
  }

  virtual HRESULT STDMETHODCALLTYPE Activate(
      _In_ LPCWSTR appUserModelId,
      _In_ LPCWSTR invokedArgs,
      _In_reads_(dataCount) const NOTIFICATION_USER_INPUT_DATA *data,
      ULONG dataCount
  ) override {
    std::wstring arguments(invokedArgs);

    std::map<std::wstring, std::wstring> inputs;
    for (unsigned int i = 0; i < dataCount; i++) {
      inputs[data[i].Key] = data[i].Value;
    }

    std::wcout << L"arguments" << arguments << L"." << std::endl;

//    auto *instance = NotificationManagerWrl::GetInstance();
//    instance->DispatchActivatedEvent(arguments, inputs);

    return S_OK;
  }

  ~NotificationActivator() {
  }
};

// Flag class as COM creatable
//CoCreatableClass(NotificationActivator)

class NotificationManagerWrlImpl : public NotificationManagerWrl {

 public:

  void Register(std::wstring aumId, std::wstring displayName, std::wstring icon_path) override;

  HRESULT ShowToast(std::wstring xml, std::wstring tag, std::wstring group, int64_t expiration_time) override;

  void Clear() override;

  void Remove(std::wstring tag, std::wstring group) override;

};

// static
NotificationManagerWrl *NotificationManagerWrl::GetInstance() {
  static NotificationManagerWrlImpl instance;
  return &instance;
}

void NotificationManagerWrlImpl::Register(std::wstring aumId, std::wstring displayName, std::wstring icon_path) {
  NotificationActivator::Register();

//  DesktopNotificationManagerCompat::RegisterActivator();
}

HRESULT NotificationManagerWrlImpl::ShowToast(
    std::wstring xml,
    std::wstring tag,
    std::wstring group,
    int64_t expiration_time
) {

  HRESULT hr;

  ComPtr<IXmlDocument> doc;
  hr = DesktopNotificationManagerCompat::CreateXmlDocumentFromString(xml.c_str(), &doc);
  RETURN_IF_FAILED(hr);

  ComPtr<IToastNotifier> notifier;
  hr = DesktopNotificationManagerCompat::CreateToastNotifier(&notifier);
  RETURN_IF_FAILED(hr);

  ComPtr<IToastNotification> toast;
  hr = DesktopNotificationManagerCompat::CreateToastNotification(doc.Get(), &toast);
  RETURN_IF_FAILED(hr);

  IToastNotification2 *toast2_ptr;
  hr = toast->QueryInterface(&toast2_ptr);
  RETURN_IF_FAILED(hr);

  ComPtr<IToastNotification2> toast2;
  toast2.Attach(toast2_ptr);

  if (!tag.empty()) {
    HSTRING tag_hstring;

    hr = ::WindowsCreateString(tag.c_str(), static_cast<UINT32>(tag.length()), &tag_hstring);
    RETURN_IF_FAILED(hr);
    hr = toast2->put_Tag(tag_hstring);
    RETURN_IF_FAILED(hr);
    ::WindowsDeleteString(tag_hstring);
  }

  if (!group.empty()) {
    HSTRING group_hstring;
    hr = ::WindowsCreateString(group.c_str(), static_cast<UINT32>(group.length()), &group_hstring);
    RETURN_IF_FAILED(hr);
    hr = toast2->put_Group(group_hstring);
    RETURN_IF_FAILED(hr);
  }

  EventRegistrationToken dismissedToken;
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
  RETURN_IF_FAILED(hr);
  hr = notifier->Show(toast.Get());
  return hr;
}

void NotificationManagerWrlImpl::Clear() {
  std::unique_ptr<DesktopNotificationHistoryCompat> history;
  auto hr = DesktopNotificationManagerCompat::get_History(&history);
  if (SUCCEEDED(hr)) {
    // Clear all toasts
    hr = history->Clear();
  }
}

void NotificationManagerWrlImpl::Remove(std::wstring tag, std::wstring group) {
  std::unique_ptr<DesktopNotificationHistoryCompat> history;
  auto hr = DesktopNotificationManagerCompat::get_History(&history);
  if (SUCCEEDED(hr)) {
    if (!tag.empty() && !group.empty()) {
      // Remove a specific toast
      hr = history->RemoveGroupedTag(tag.c_str(), group.c_str());
    } else if (!tag.empty()) {
      // Remove all toasts with a specific tag
      hr = history->Remove(tag.c_str());
    } else if (!group.empty()) {
      // Remove all toasts with a specific group
      hr = history->RemoveGroup(group.c_str());
    }
  }
}

#endif // WIN_TOAST_ENABLE_WRL
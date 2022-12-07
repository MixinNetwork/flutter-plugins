//
// Created by yangbin on 2022/12/6.
//

#ifdef WIN_TOAST_ENABLE_WIN_RT

#include "notification_manager_win_rt.h"

#include "DesktopNotificationManagerCompat.h"
#include <winrt/Windows.Data.Xml.Dom.h>
#include <iostream>

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;
using namespace notification_rt;

void NotificationManagerWinRT::Register(
    std::wstring aumId, std::wstring displayName,
    std::wstring icon_path) {
  DesktopNotificationManagerCompat::Register(aumId, displayName, icon_path);
  DesktopNotificationManagerCompat::OnActivated([this](DesktopNotificationActivatedEventArgsCompat data) {
    if (!activated_callback_) {
      return;
    }
    std::wstring tag = data.Argument();
    std::map<std::wstring, std::wstring> user_inputs;
    for (auto &&input : data.UserInput()) {
      user_inputs[input.Key().c_str()] = input.Value().c_str();
    }
    activated_callback_(tag, user_inputs);
  });
}

HRESULT NotificationManagerWinRT::ShowToast(
    std::wstring xml,
    std::wstring tag,
    std::wstring group,
    int64_t expiration_time
) {
  try {

    // Construct the toast template
    XmlDocument doc;
    doc.LoadXml(xml);

    // Construct the notification
    ToastNotification notification{doc};

    if (!tag.empty()) {
      notification.Tag(tag);
    }
    if (!group.empty()) {
      notification.Group(group);
    }

    if (expiration_time != 0) {
      Windows::Foundation::TimeSpan millis(expiration_time);
      notification.ExpirationTime(Windows::Foundation::DateTime(millis));
    }

    notification.Dismissed([this](const ToastNotification &sender, const ToastDismissedEventArgs &args) {
      if (!dismissed_callback_) {
        return;
      }
      dismissed_callback_(
          sender.Tag().c_str(),
          sender.Group().c_str(),
          static_cast<int>(args.Reason())
      );
    });

    DesktopNotificationManagerCompat::CreateToastNotifier().Show(notification);
  } catch (hresult_error const &e) {
    std::wcout << "show failed: " << e.message().c_str() << std::endl;
    return e.code();
  }
  return S_OK;
}

void NotificationManagerWinRT::Clear() {
  try {
    DesktopNotificationManagerCompat::History().Clear();
  } catch (const hresult_error &e) {
    std::cout << "Clear failed: " << e.message().c_str() << std::endl;
  }
}

void NotificationManagerWinRT::Remove(std::wstring tag, std::wstring group) {
  try {
    if (!tag.empty() && !group.empty()) {
      DesktopNotificationManagerCompat::History().Remove(tag, group);
    } else if (!group.empty()) {
      DesktopNotificationManagerCompat::History().RemoveGroup(group);
    } else if (!tag.empty()) {
      DesktopNotificationManagerCompat::History().Remove(tag);
    }
  } catch (hresult_error const &e) {
    std::wcout << "Remove failed: " << e.code() << "error: " << e.message().c_str() << std::endl;
  }
}

#endif //WIN_TOAST_ENABLE_WIN_RT

//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include <hstring.h>
#include <minappmodel.h>

#include "notification_manager.h"
#include "dll_importer.h"

#include "DesktopNotificationManagerCompat.h"
#include <winrt/Windows.Data.Xml.Dom.h>
#include <iostream>
#include <utility>

namespace {

bool _checkedHasIdentity = false;
bool _hasIdentity = false;

bool hasIdentity() {
  // https://stackoverflow.com/questions/39609643/determine-if-c-application-is-running-as-a-uwp-app-in-desktop-bridge-project
  UINT32 length;
  wchar_t packageFamilyName[PACKAGE_FAMILY_NAME_MAX_LENGTH + 1];
  LONG result = DllImporter::GetPackageFamilyName(GetCurrentProcess(), &length, packageFamilyName);
  return result == ERROR_SUCCESS;
}

}

bool NotificationManager::HasIdentity() {
  if (!_checkedHasIdentity) {
    _hasIdentity = hasIdentity();
    _checkedHasIdentity = true;
  }

  return _hasIdentity;
}

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;
using namespace notification_rt;

NotificationManager::NotificationManager() = default;

NotificationManager::~NotificationManager() {
  if (registered_) {
    try {
      DesktopNotificationManagerCompat::OnActivated(nullptr);
      DesktopNotificationManagerCompat::Uninstall();
    } catch (...) {
      // ignore
    }
  }
}

void NotificationManager::Register(
    std::wstring aumId, std::wstring displayName,
    std::wstring icon_path, std::wstring clsid) {
  DesktopNotificationManagerCompat::Register(std::move(aumId), displayName, icon_path, clsid);
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
  registered_ = true;
}

void NotificationManager::ShowToast(
    const std::wstring &xml,
    const std::wstring &tag,
    const std::wstring &group,
    int64_t expiration_time
) {
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

}

void NotificationManager::Clear() {
  DesktopNotificationManagerCompat::History().Clear();
}

void NotificationManager::Remove(std::wstring tag, std::wstring group) {
  if (!tag.empty() && !group.empty()) {
    DesktopNotificationManagerCompat::History().Remove(tag, group);
  } else if (!group.empty()) {
    DesktopNotificationManagerCompat::History().RemoveGroup(group);
  } else if (!tag.empty()) {
    DesktopNotificationManagerCompat::History().Remove(tag);
  }
}

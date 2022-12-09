//
// Created by yangbin on 2022/12/6.
//

#ifndef WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_H_
#define WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_H_

#include "Windows.h"
#include <string>
#include <functional>
#include <map>
#include <utility>

class NotificationManager {

 public:

  static bool HasIdentity();

  NotificationManager();

  ~NotificationManager();

  void Register(
      std::wstring aumId,
      std::wstring displayName,
      std::wstring icon_path,
      std::wstring clsid
  );

  void ShowToast(
      const std::wstring& xml,
      const std::wstring& tag,
      const std::wstring& group,
      int64_t expiration_time
  );

  using ActivatedCallback = std::function<void(std::wstring, std::map<std::wstring, std::wstring>)>;

  void OnActivated(ActivatedCallback callback) {
    activated_callback_ = std::move(callback);
  }

  using DismissedCallback = std::function<void(std::wstring tag, std::wstring group, int reason)>;
  void OnDismissed(DismissedCallback callback) {
    dismissed_callback_ = std::move(callback);
  }

  void Clear();

  void Remove(std::wstring tag, std::wstring group);

 private:

  ActivatedCallback activated_callback_;
  DismissedCallback dismissed_callback_;

  bool registered_ = false;
};

#endif //WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_H_

//
// Created by yangbin on 2022/12/6.
//

#ifndef WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_WRL_H_
#define WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_WRL_H_

#ifdef WIN_TOAST_ENABLE_WRL

#include <utility>

#include "notification_manager.h"

class NotificationManagerWrl : public NotificationManager {

 public:

  static NotificationManagerWrl *GetInstance() {
    static NotificationManagerWrl instance;
    return &instance;
  }

  void Register(std::wstring aumId, std::wstring displayName, std::wstring icon_path) override;

  HRESULT ShowToast(std::wstring xml, std::wstring tag, std::wstring group, int64_t expiration_time) override;

  void Clear() override;

  void Remove(std::wstring tag, std::wstring group) override;

  void DispatchActivatedEvent(std::wstring arguments, std::map<std::wstring, std::wstring> inputs) {
    if (activated_callback_) {
      activated_callback_(std::move(arguments), std::move(inputs));
    }
  }

};

#endif //WIN_TOAST_ENABLE_WRL

#endif //WIN_TOAST_WINDOWS_NOTIFICATION_MANAGER_WRL_H_

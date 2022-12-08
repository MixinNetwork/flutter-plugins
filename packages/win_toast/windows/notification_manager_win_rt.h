//
// Created by yangbin on 2022/12/6.
//

#ifndef WIN_TOAST_WINDOWS_INCLUDE_NOTIFICATION_MANAGER_WIN_RT_H_
#define WIN_TOAST_WINDOWS_INCLUDE_NOTIFICATION_MANAGER_WIN_RT_H_


#include "notification_manager.h"

class NotificationManagerWinRT : public NotificationManager {

 public:

  static NotificationManagerWinRT *GetInstance() {
    static NotificationManagerWinRT instance;
    return &instance;
  }

  void Register(std::wstring aumId, std::wstring displayName,
                std::wstring icon_path, std::wstring clsid) override;
  HRESULT ShowToast(std::wstring xml, std::wstring tag, std::wstring group, int64_t expiration_time) override;
  void Clear() override;
  void Remove(std::wstring tag, std::wstring group) override;

};


#endif //WIN_TOAST_WINDOWS_INCLUDE_NOTIFICATION_MANAGER_WIN_RT_H_

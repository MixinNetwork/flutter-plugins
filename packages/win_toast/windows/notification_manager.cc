//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include "notification_manager.h"

#include "appmodel.h"

namespace {
bool _checkedHasIdentity;
bool _hasIdentity;
}

bool NotificationManager::HasIdentity() {
  if (!_checkedHasIdentity) {
    // https://stackoverflow.com/questions/39609643/determine-if-c-application-is-running-as-a-uwp-app-in-desktop-bridge-project
    UINT32 length;
    wchar_t packageFamilyName[PACKAGE_FAMILY_NAME_MAX_LENGTH + 1];
    LONG result = GetPackageFamilyName(GetCurrentProcess(), &length, packageFamilyName);
    _hasIdentity = result == ERROR_SUCCESS;

    _checkedHasIdentity = true;
  }

  return _hasIdentity;
}

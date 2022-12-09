//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include <hstring.h>
#include <minappmodel.h>

#include "notification_manager.h"
#include "dll_importer.h"

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


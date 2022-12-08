//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include <hstring.h>

#include "notification_manager.h"
#include "dll_importer.h"

namespace {

bool _checkedHasIdentity = false;
bool _hasIdentity = false;

bool hasIdentity() {
  UINT32 length;
  auto err = DllImporter::GetCurrentPackageFullName(&length, nullptr);
  if (err != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }

  auto fullName = (PWSTR) malloc(length * sizeof(PWSTR));
  if (fullName == nullptr) {
    return false;
  }

  err = DllImporter::GetCurrentPackageFullName(&length, fullName);
  if (err != ERROR_SUCCESS) {
    return false;
  }

  free(fullName);
  return true;
}

}

bool NotificationManager::HasIdentity() {
  if (!_checkedHasIdentity) {
    _hasIdentity = true;
    _checkedHasIdentity = true;
  }

  return _hasIdentity;
}

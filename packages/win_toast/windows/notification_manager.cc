//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include <appmodel.h>
#include <malloc.h>
#include <stdio.h>
#include <hstring.h>
#include <minappmodel.h>

#include "notification_manager.h"
#include "dll_importer.h"

namespace
{

  bool _checkedHasIdentity = false;
  bool _hasIdentity = false;

  // https://learn.microsoft.com/en-us/windows/msix/detect-package-identity
  bool hasIdentity()
  {
    UINT32 length = 0;
    LONG rc = GetCurrentPackageFullName(&length, NULL);
    if (rc != ERROR_INSUFFICIENT_BUFFER)
    {
      if (rc == APPMODEL_ERROR_NO_PACKAGE)
        wprintf(L"Process has no package identity\n");
      else
        wprintf(L"Error %d in GetCurrentPackageFullName\n", rc);
      return false;
    }

    PWSTR fullName = (PWSTR)malloc(length * sizeof(*fullName));
    if (fullName == NULL)
    {
      wprintf(L"Error allocating memory\n");
      return false;
    }

    rc = GetCurrentPackageFullName(&length, fullName);
    if (rc != ERROR_SUCCESS)
    {
      wprintf(L"Error %d retrieving PackageFullName\n", rc);
      return false;
    }
    wprintf(L"%s\n", fullName);

    free(fullName);

    return true;
  }

}

bool NotificationManager::HasIdentity()
{
  if (!_checkedHasIdentity)
  {
    _hasIdentity = hasIdentity();
    _checkedHasIdentity = true;
  }

  return _hasIdentity;
}

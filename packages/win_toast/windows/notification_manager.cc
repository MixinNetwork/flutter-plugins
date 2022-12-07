//
// Created by yangbin on 2022/12/6.
//

#include <Windows.h>
#include <hstring.h>

#include "notification_manager.h"

namespace DllImporter {

static bool isLoaded = false;

// Function load a function from library
template<typename Function>
HRESULT loadFunctionFromLibrary(HINSTANCE library, LPCSTR name, Function &func) {
  if (!library) {
    return E_INVALIDARG;
  }
  func = reinterpret_cast<Function>(GetProcAddress(library, name));
  return (func != nullptr) ? S_OK : E_FAIL;
}

typedef HRESULT(FAR STDAPICALLTYPE *f_GetCurrentPackageFullName)
    (_Inout_ UINT32 *packageFullNameLength, _Out_writes_opt_(*packageFullNameLength) PWSTR packageFullName);

static f_GetCurrentPackageFullName GetCurrentPackageFullName;

inline HRESULT initialize() {
  if (isLoaded) {
    return S_OK;
  }
  HRESULT hr;
  HINSTANCE LibKernel32 = LoadLibraryW(L"KERNEL32.DLL");
  hr = loadFunctionFromLibrary(LibKernel32, "GetCurrentPackageFullName", GetCurrentPackageFullName);
  if (SUCCEEDED(hr)) {
    isLoaded = true;
  }
  return hr;
}
}

namespace {

bool _checkedHasIdentity;
bool _hasIdentity;

bool hasIdentity() {
  auto hr = DllImporter::initialize();
  if (!SUCCEEDED(hr)) {
    return false;
  }

  UINT32 length;
  auto err = DllImporter::GetCurrentPackageFullName(&length, nullptr);
  if (err != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }

  PWSTR fullName = (PWSTR) malloc(length * sizeof(*fullName));
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
    _hasIdentity = hasIdentity();
    _checkedHasIdentity = true;
  }

  return _hasIdentity;
}

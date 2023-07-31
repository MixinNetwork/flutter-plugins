// ******************************************************************
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THE CODE IS PROVIDED 揂S IS? WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE CODE OR THE USE OR OTHER DEALINGS IN THE CODE.
// ******************************************************************

#include "pch.h"
#include "DesktopNotificationManagerCompat.h"

#include <winrt/Windows.ApplicationModel.h>
#include <Windows.h>
#include "notification_manager.h"
#include "NotificationActivationCallback.h"
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Foundation.Collections.h>

namespace notification_rt {

using namespace winrt;
using namespace Windows::ApplicationModel;
using namespace Windows::UI::Notifications;
using namespace Windows::Foundation::Collections;

struct Win32AppInfo {
  std::wstring Aumid;
  std::wstring DisplayName;
  std::wstring IconPath;
};

bool IsContainerized();
bool HasIdentity();
void SetRegistryKeyValue(HKEY hKey, std::wstring subKey, std::wstring valueName, std::wstring value);
void DeleteRegistryKeyValue(HKEY hKey, std::wstring subKey, std::wstring valueName);
void DeleteRegistryKey(HKEY hKey, std::wstring subKey);
void EnsureRegistered();
std::wstring CreateAndRegisterActivator();
std::wstring GenerateGuid(std::wstring name);
std::wstring get_module_path();
void RegisterActivatorWithClsid(std::wstring clsidStr);

std::wstring _win32Aumid;
std::function<void(DesktopNotificationActivatedEventArgsCompat)> _onActivated = nullptr;

void DesktopNotificationManagerCompat::Register(
    std::wstring aumid,
    std::wstring displayName,
    std::wstring iconPath,
    std::wstring clsid
) {
  // If has identity
  if (HasIdentity()) {
    RegisterActivatorWithClsid(clsid);
    // No need to do anything additional, already registered through manifest
    // register callback
    return;
  }

  _win32Aumid = aumid;

  std::wstring clsidStr = CreateAndRegisterActivator();

  // Register via registry
  std::wstring subKey = LR"(SOFTWARE\Classes\AppUserModelId\)" + _win32Aumid;

  // Set the display name and icon uri
  SetRegistryKeyValue(HKEY_CURRENT_USER, subKey, L"DisplayName", displayName);

  if (!iconPath.empty()) {
    SetRegistryKeyValue(HKEY_CURRENT_USER, subKey, L"IconUri", iconPath);
  } else {
    DeleteRegistryKeyValue(HKEY_CURRENT_USER, subKey, L"IconUri");
  }

  // Background color only appears in the settings page, format is
  // hex without leading #, like "FFDDDDDD"
  SetRegistryKeyValue(HKEY_CURRENT_USER, subKey, L"IconBackgroundColor", iconPath);

  SetRegistryKeyValue(HKEY_CURRENT_USER, subKey, L"CustomActivator", L"{" + clsidStr + L"}");
}

void DesktopNotificationManagerCompat::OnActivated(std::function<void(DesktopNotificationActivatedEventArgsCompat)> callback) {
  EnsureRegistered();

  _onActivated = callback;
}

void EnsureRegistered() {
  if (!HasIdentity() && _win32Aumid.empty()) {
    throw "Must call Register first.";
  }
}

ToastNotifier DesktopNotificationManagerCompat::CreateToastNotifier() {
  if (HasIdentity()) {
    return ToastNotificationManager::CreateToastNotifier();
  } else {
    return ToastNotificationManager::CreateToastNotifier(_win32Aumid);
  }
}

void DesktopNotificationManagerCompat::Uninstall() {
  if (IsContainerized()) {
    // Packaged containerized apps automatically clean everything up already
    return;
  }

  if (!HasIdentity() && !_win32Aumid.empty()) {
    try {
      // Remove all scheduled notifications (do this first before clearing current notifications)
      auto notifier = CreateToastNotifier();
      auto scheduled = notifier.GetScheduledToastNotifications();
      for (unsigned int i = 0; i < scheduled.Size(); i++) {
        try {
          notifier.RemoveFromSchedule(scheduled.GetAt(i));
        }
        catch (...) {}
      }
    }
    catch (...) {}

    try {
      // Clear all current notifications
      History().Clear();
    }
    catch (...) {}
  }

  try {
    // Remove registry key
    if (!_win32Aumid.empty()) {
      std::wstring subKey = LR"(SOFTWARE\Classes\AppUserModelId\)" + _win32Aumid;
      DeleteRegistryKey(HKEY_CURRENT_USER, subKey);
    }
  }
  catch (...) {}
}

std::wstring GenerateGuid(std::wstring name) {
  // From https://stackoverflow.com/a/41622689/1454643
  if (name.length() <= 16) {
    wchar_t guid[36];
    swprintf_s(
        guid,
        36,
        L"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        name[0],
        name[1],
        name[2],
        name[3],
        name[4],
        name[5],
        name[6],
        name[7],
        name[8],
        name[9],
        name[10],
        name[11],
        name[12],
        name[13],
        name[14],
        name[15]);
    return guid;
  } else {
    std::size_t hash = std::hash<std::wstring>{}(name);

    // Only ever at most 20 chars long
    std::wstring hashStr = std::to_wstring(hash);

    wchar_t guid[37];
    for (int i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        guid[i] = '-';
      } else {
        int strPos = i;
        if (i > 23) {
          strPos -= 4;
        } else if (i > 18) {
          strPos -= 3;
        } else if (i > 13) {
          strPos -= 2;
        } else if (i > 8) {
          strPos -= 1;
        }

        if (strPos < hashStr.length()) {
          guid[i] = hashStr[strPos];
        } else {
          guid[i] = '0';
        }
      }
    }

    guid[36] = '\0';

    return guid;
  }
}

// https://docs.microsoft.com/en-us/windows/uwp/cpp-and-winrt-apis/author-coclasses#implement-the-coclass-and-class-factory
struct callback : implements<callback, INotificationActivationCallback> {
  HRESULT __stdcall Activate(
      LPCWSTR appUserModelId,
      LPCWSTR invokedArgs,
      [[maybe_unused]] NOTIFICATION_USER_INPUT_DATA const *data,
      [[maybe_unused]] ULONG dataCount) noexcept {
    if (_onActivated != nullptr) {
      std::wstring argument(invokedArgs);

      StringMap userInput;

      for (unsigned int i = 0; i < dataCount; i++) {
        userInput.Insert(data[i].Key, data[i].Value);
      }

      DesktopNotificationActivatedEventArgsCompat args(argument, userInput);
      _onActivated(args);
    }
    return S_OK;
  }
};

struct callback_factory : implements<callback_factory, IClassFactory> {
  HRESULT __stdcall CreateInstance(
      IUnknown *outer,
      GUID const &iid,
      void **result) noexcept {
    *result = nullptr;

    if (outer) {
      return CLASS_E_NOAGGREGATION;
    }

    return make<callback>()->QueryInterface(iid, result);
  }

  HRESULT __stdcall LockServer(BOOL) noexcept {
    return S_OK;
  }
};

void RegisterActivatorWithClsid(std::wstring clsidStr) {
  DWORD registration{};
  GUID clsid;
  winrt::check_hresult(::CLSIDFromString((L"{" + clsidStr + L"}").c_str(), &clsid));

  // Register callback
  winrt::check_hresult(CoRegisterClassObject(
      clsid,
      make<callback_factory>().get(),
      CLSCTX_LOCAL_SERVER,
      REGCLS_MULTIPLEUSE,
      &registration)
  );
}

std::wstring CreateAndRegisterActivator() {

  std::wstring clsidStr = GenerateGuid(_win32Aumid);

  RegisterActivatorWithClsid(clsidStr);

  // Create launch path+args
  // Include a flag so we know this was a toast activation and should wait for COM to process
  // We also wrap EXE path in quotes for extra security
  std::string launchArg = TOAST_ACTIVATED_LAUNCH_ARG;
  std::wstring launchArgW(launchArg.begin(), launchArg.end());
  std::wstring launchStr = L"\"" + get_module_path() + L"\" " + launchArgW;

  // Update registry with activator
  std::wstring key_path = LR"(SOFTWARE\Classes\CLSID\{)" + clsidStr + LR"(}\LocalServer32)";
  SetRegistryKeyValue(HKEY_CURRENT_USER, key_path, L"", launchStr);

  return clsidStr;
}

std::wstring get_module_path() {
  std::wstring path(100, L'?');
  uint32_t path_size{};
  DWORD actual_size{};

  do {
    path_size = static_cast<uint32_t>(path.size());
    actual_size = ::GetModuleFileName(nullptr, path.data(), path_size);

    if (actual_size + 1 > path_size) {
      path.resize(path_size * 2, L'?');
    }
  } while (actual_size + 1 > path_size);

  path.resize(actual_size);
  return path;
}

void SetRegistryKeyValue(HKEY hKey, std::wstring subKey, std::wstring valueName, std::wstring value) {
  winrt::check_hresult(::RegSetKeyValue(
      hKey,
      subKey.c_str(),
      valueName.empty() ? nullptr : valueName.c_str(),
      REG_SZ,
      reinterpret_cast<const BYTE *>(value.c_str()),
      static_cast<DWORD>((value.length() + 1) * sizeof(WCHAR))));
}

void DeleteRegistryKeyValue(HKEY hKey, std::wstring subKey, std::wstring valueName) {
  winrt::check_hresult(::RegDeleteKeyValue(
      hKey,
      subKey.c_str(),
      valueName.c_str()));
}

void DeleteRegistryKey(HKEY hKey, std::wstring subKey) {
  winrt::check_hresult(::RegDeleteKey(
      hKey,
      subKey.c_str()));
}

bool _checkedIsContainerized;
bool _isContainerized;
bool IsContainerized() {
  if (!_checkedIsContainerized) {
    // If MSIX or sparse
    if (HasIdentity()) {
      // Sparse is identified if EXE is running outside of installed package location
      winrt::hstring packageInstalledLocation = Package::Current().InstalledLocation().Path();
      wchar_t exePath[MAX_PATH];
      DWORD charWritten = GetModuleFileNameW(nullptr, exePath, ARRAYSIZE(exePath));
      if (charWritten == 0) {
        throw HRESULT_FROM_WIN32(GetLastError());
      }

      // If inside package location
      std::wstring stdExePath = exePath;
      if (stdExePath.find(packageInstalledLocation.c_str()) == 0) {
        _isContainerized = true;
      } else {
        _isContainerized = false;
      }
    }

      // Plain Win32
    else {
      _isContainerized = false;
    }

    _checkedIsContainerized = true;
  }

  return _isContainerized;
}

bool HasIdentity() {
  return NotificationManager::HasIdentity();
}

DesktopNotificationHistoryCompat DesktopNotificationManagerCompat::History() {
  EnsureRegistered();

  DesktopNotificationHistoryCompat history(_win32Aumid);
  return history;
}

void DesktopNotificationHistoryCompat::Clear() {
  if (_win32Aumid.empty()) {
    _history.Clear();
  } else {
    _history.Clear(_win32Aumid);
  }
}

IVectorView<ToastNotification> DesktopNotificationHistoryCompat::GetHistory() {
  if (_win32Aumid.empty()) {
    return _history.GetHistory();
  } else {
    return _history.GetHistory(_win32Aumid);
  }
}

void DesktopNotificationHistoryCompat::Remove(std::wstring tag) {
  if (_win32Aumid.empty()) {
    _history.Remove(tag);
  } else {
    _history.Remove(tag, L"", _win32Aumid);
  }
}

void DesktopNotificationHistoryCompat::Remove(std::wstring tag, std::wstring group) {
  if (_win32Aumid.empty()) {
    _history.Remove(tag, group);
  } else {
    _history.Remove(tag, group, _win32Aumid);
  }
}

void DesktopNotificationHistoryCompat::RemoveGroup(std::wstring group) {
  if (_win32Aumid.empty()) {
    _history.RemoveGroup(group);
  } else {
    _history.RemoveGroup(group, _win32Aumid);
  }
}

}


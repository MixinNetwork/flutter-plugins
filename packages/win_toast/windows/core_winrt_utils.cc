//
// Created by yangbin on 2022/12/8.
//

#include "core_winrt_utils.h"

#include <hstring.h>
#include <winstring.h>

namespace base {

FARPROC LoadComBaseFunction(const char *name) {
  auto module = LoadLibraryEx(L"combase.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (module == nullptr) {
    return nullptr;
  }
  return GetProcAddress(module, name);
}

decltype(&::WindowsCreateString) GetWindowsCreateString() {
  static auto func = (decltype(&WindowsCreateString)) LoadComBaseFunction("WindowsCreateString");
  return func;
}

decltype(&::WindowsDeleteString) GetWindowsDeleteString() {
  static auto func = (decltype(&WindowsDeleteString)) LoadComBaseFunction("WindowsDeleteString");
  return func;
}

decltype(&::WindowsGetStringRawBuffer) GetWindowsGetStringRawBuffer() {
  static auto func = (decltype(&WindowsGetStringRawBuffer)) LoadComBaseFunction("WindowsGetStringRawBuffer");
  return func;
}

decltype(&::RoInitialize) GetRoInitialize() {
  static auto func = (decltype(&RoInitialize)) LoadComBaseFunction("RoInitialize");
  return func;
}

decltype(&::RoUninitialize) GetRoUninitialize() {
  static auto func = (decltype(&RoUninitialize)) LoadComBaseFunction("RoUninitialize");
  return func;
}

decltype(&::RoActivateInstance) GetRoActivateInstance() {
  static auto func = (decltype(&RoActivateInstance)) LoadComBaseFunction("RoActivateInstance");
  return func;
}

decltype(&::RoGetActivationFactory) GetRoGetActivationFactory() {
  static auto func = (decltype(&RoGetActivationFactory)) LoadComBaseFunction("RoGetActivationFactory");
  return func;
}

HRESULT WindowsCreateString(const wchar_t *sourceString, UINT32 length, HSTRING *hstring) {
  auto func = GetWindowsCreateString();
  if (func == nullptr) {
    return E_FAIL;
  }
  return func(sourceString, length, hstring);
}

HRESULT WindowsDeleteString(HSTRING hstring) {
  auto func = GetWindowsDeleteString();
  if (func == nullptr) {
    return E_FAIL;
  }
  return func(hstring);
}

PCWSTR WindowsGetStringRawBuffer(HSTRING hstring, UINT32 *length) {
  auto func = GetWindowsGetStringRawBuffer();
  if (func == nullptr) {
    *length = 0;
    return nullptr;
  }
  return func(hstring, length);
}

}

win_utils::ScopedHString::ScopedHString(HSTRING hstring) : hstring_(hstring) {

}

win_utils::ScopedHString win_utils::ScopedHString::Create(std::wstring string) {
  HSTRING hstring;
  HRESULT result = base::WindowsCreateString(string.c_str(), static_cast<UINT32>(string.size()), &hstring);
  if (SUCCEEDED(result)) {
    return ScopedHString(hstring);
  }
  return win_utils::ScopedHString(nullptr);
}

win_utils::ScopedHString::~ScopedHString() {
  base::WindowsDeleteString(hstring_);
}

HRESULT win_utils::RoInitialize(RO_INIT_TYPE init_type) {
  auto func = base::GetRoInitialize();
  if (func == nullptr) {
    return E_FAIL;
  }
  return func(init_type);
}
void win_utils::RoUninitialize() {
  auto func = base::GetRoUninitialize();
  if (func) {
    func();
  }
}

HRESULT win_utils::RoActivateInstance(HSTRING activatable_class_id, IInspectable **instance) {
  auto func = base::GetRoActivateInstance();
  if (func == nullptr) {
    return E_FAIL;
  }
  return func(activatable_class_id, instance);
}

HRESULT win_utils::RoGetActivationFactory(HSTRING activatable_class_id, const IID &iid, void **factory) {
  auto func = base::GetRoGetActivationFactory();
  if (func == nullptr) {
    return E_FAIL;
  }
  return func(activatable_class_id, iid, factory);
}

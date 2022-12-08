//
// Created by yangbin on 2022/12/8.
//

#include "dll_importer.h"

namespace {

static bool is_dll_load_called = false;
static HRESULT dll_load_result = E_FAIL;

// Function load a function from library
template<typename Function>
HRESULT loadFunctionFromLibrary(HINSTANCE library, LPCSTR name, Function &func) {
  if (!library) {
    return E_INVALIDARG;
  }
  func = reinterpret_cast<Function>(GetProcAddress(library, name));
  return (func != nullptr) ? S_OK : E_FAIL;
}

HRESULT LoadFunctions() {
  HINSTANCE LibKernel32 = LoadLibraryW(L"KERNEL32.DLL");

  RETURN_IF_FAILED(loadFunctionFromLibrary(LibKernel32, "GetPackageFamilyName",
                                           DllImporter::GetPackageFamilyName));

  return S_OK;
}

}

DllImporter::f_GetPackageFamilyName DllImporter::GetPackageFamilyName;

HRESULT DllImporter::Initialize() {
  if (is_dll_load_called) {
    return dll_load_result;
  }
  dll_load_result = LoadFunctions();
  is_dll_load_called = true;

  return dll_load_result;
}

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

  RETURN_IF_FAILED(loadFunctionFromLibrary(LibKernel32, "GetCurrentPackageFullName",
                                           DllImporter::GetCurrentPackageFullName));
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibKernel32, "GetPackageFamilyName",
                                           DllImporter::GetPackageFamilyName));

  HINSTANCE LibShell32 = LoadLibraryW(L"SHELL32.DLL");
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibShell32, "SetCurrentProcessExplicitAppUserModelID",
                                           DllImporter::SetCurrentProcessExplicitAppUserModelID));

  HINSTANCE LibPropSys = LoadLibraryW(L"PROPSYS.DLL");
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibPropSys, "PropVariantToString",
                                           DllImporter::PropVariantToString));

  HINSTANCE LibComBase = LoadLibraryW(L"COMBASE.DLL");
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibComBase, "RoGetActivationFactory",
                                           DllImporter::RoGetActivationFactory));

  RETURN_IF_FAILED(loadFunctionFromLibrary(LibComBase, "WindowsCreateStringReference",
                                           DllImporter::WindowsCreateStringReference));
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibComBase, "WindowsGetStringRawBuffer",
                                           DllImporter::WindowsGetStringRawBuffer));
  RETURN_IF_FAILED(loadFunctionFromLibrary(LibComBase, "WindowsDeleteString",
                                           DllImporter::WindowsDeleteString));
  return S_OK;
}

}

DllImporter::f_RoGetActivationFactory DllImporter::RoGetActivationFactory;
DllImporter::f_WindowsCreateStringReference DllImporter::WindowsCreateStringReference;
DllImporter::f_WindowsGetStringRawBuffer DllImporter::WindowsGetStringRawBuffer;
DllImporter::f_WindowsDeleteString DllImporter::WindowsDeleteString;
DllImporter::f_GetCurrentPackageFullName DllImporter::GetCurrentPackageFullName;
DllImporter::f_SetCurrentProcessExplicitAppUserModelID DllImporter::SetCurrentProcessExplicitAppUserModelID;
DllImporter::f_PropVariantToString DllImporter::PropVariantToString;
DllImporter::f_GetPackageFamilyName DllImporter::GetPackageFamilyName;


HRESULT DllImporter::Initialize() {
  if (is_dll_load_called) {
    return dll_load_result;
  }
  dll_load_result = LoadFunctions();
  is_dll_load_called = true;

  return dll_load_result;
}

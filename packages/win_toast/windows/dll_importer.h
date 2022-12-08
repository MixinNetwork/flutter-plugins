//
// Created by yangbin on 2022/12/8.
//

#ifndef WIN_TOAST_WINDOWS_DLL_IMPORTER_H_
#define WIN_TOAST_WINDOWS_DLL_IMPORTER_H_

#include <Windows.h>
#include <hstring.h>

#define RETURN_IF_FAILED(hr) do { HRESULT _hrTemp = hr; if (FAILED(_hrTemp)) { return _hrTemp; } } while (false)

class DllImporter {

 public:

  typedef HRESULT(FAR STDAPICALLTYPE *f_SetCurrentProcessExplicitAppUserModelID)(__in PCWSTR AppID);
  typedef HRESULT
  (FAR STDAPICALLTYPE *f_PropVariantToString)(_In_ REFPROPVARIANT propvar, _Out_writes_(cch) PWSTR psz, _In_ UINT cch);
  typedef HRESULT(FAR STDAPICALLTYPE *f_RoGetActivationFactory)
      (_In_ HSTRING activatableClassId, _In_ REFIID iid, _COM_Outptr_ void **factory);
  typedef HRESULT(FAR STDAPICALLTYPE *f_WindowsCreateStringReference)(_In_reads_opt_(length + 1)
                                                                      PCWSTR sourceString,
                                                                      UINT32 length,
                                                                      _Out_
                                                                      HSTRING_HEADER *hstringHeader,
                                                                      _Outptr_result_maybenull_
                                                                      _Result_nullonfailure_
                                                                      HSTRING *string);
  typedef PCWSTR(FAR STDAPICALLTYPE *f_WindowsGetStringRawBuffer)(_In_ HSTRING string, _Out_opt_ UINT32 *length);
  typedef HRESULT(FAR STDAPICALLTYPE *f_WindowsDeleteString)(_In_opt_ HSTRING string);

  typedef HRESULT(FAR STDAPICALLTYPE *f_GetCurrentPackageFullName)
      (_Inout_ UINT32 *packageFullNameLength, _Out_writes_opt_(*packageFullNameLength) PWSTR packageFullName);

  typedef HRESULT(FAR STDAPICALLTYPE *f_GetPackageFamilyName)
      (_In_ HANDLE hProcess,
       _Inout_ UINT32 *packageFamilyNameLength,
       _Out_writes_opt_(*packageFamilyNameLength) PWSTR packageFamilyName
      );

  static f_GetCurrentPackageFullName GetCurrentPackageFullName;
  static f_SetCurrentProcessExplicitAppUserModelID SetCurrentProcessExplicitAppUserModelID;
  static f_PropVariantToString PropVariantToString;
  static f_RoGetActivationFactory RoGetActivationFactory;
  static f_WindowsCreateStringReference WindowsCreateStringReference;
  static f_WindowsGetStringRawBuffer WindowsGetStringRawBuffer;
  static f_WindowsDeleteString WindowsDeleteString;
  static f_GetPackageFamilyName GetPackageFamilyName;

  static HRESULT Initialize();

};

#endif //WIN_TOAST_WINDOWS_DLL_IMPORTER_H_

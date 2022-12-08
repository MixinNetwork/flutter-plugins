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

  typedef HRESULT(FAR STDAPICALLTYPE *f_GetPackageFamilyName)
      (_In_ HANDLE hProcess,
       _Inout_ UINT32 *packageFamilyNameLength,
       _Out_writes_opt_(*packageFamilyNameLength) PWSTR packageFamilyName
      );


  static f_GetPackageFamilyName GetPackageFamilyName;

  static HRESULT Initialize();

};

#endif //WIN_TOAST_WINDOWS_DLL_IMPORTER_H_

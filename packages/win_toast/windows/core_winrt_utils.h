//
// Created by yangbin on 2022/12/8.
//

#ifndef WIN_TOAST_WINDOWS_WINRT_UTILS_H_
#define WIN_TOAST_WINDOWS_WINRT_UTILS_H_

#include <hstring.h>
#include <windef.h>
#include <roapi.h>

#include "include/win_toast/win_toast_plugin.h"

#include <string>

namespace win_utils {

class ScopedHString {
 public:
  explicit ScopedHString(HSTRING hstring);

  static ScopedHString Create(std::wstring string);

  virtual ~ScopedHString();

  [[nodiscard]] bool IsValid() const {
    return hstring_ != nullptr;
  }

  [[nodiscard]] HSTRING get() const {
    return hstring_;
  }

 private:
  HSTRING hstring_;

};

FLUTTER_PLUGIN_EXPORT HRESULT RoInitialize(RO_INIT_TYPE init_type);

FLUTTER_PLUGIN_EXPORT void RoUninitialize();

FLUTTER_PLUGIN_EXPORT HRESULT RoActivateInstance(HSTRING activatable_class_id, IInspectable **instance);

FLUTTER_PLUGIN_EXPORT HRESULT RoGetActivationFactory(HSTRING activatable_class_id, REFIID iid, void **factory);

// Retrieves and activation factory for the type specified.
template<typename InterfaceType, wchar_t const *runtime_class_id>
HRESULT GetActivationFactory(InterfaceType **factory) {
  ScopedHString hstring = ScopedHString::Create(runtime_class_id);
  if (!hstring.IsValid()) {
    return E_FAIL;
  }
  return RoGetActivationFactory(hstring.get(), IID_PPV_ARGS(factory));
}

}

#endif //WIN_TOAST_WINDOWS_WINRT_UTILS_H_

//
// Created by yangbin on 2022/12/7.
//

#ifndef WIN_TOAST_WINDOWS_WRL_COMPAT_H_
#define WIN_TOAST_WINDOWS_WRL_COMPAT_H_

// WRL
// Microsoft::WRL::Details::StaticStorage contains a programming error.
// The author attempted to create a properly aligned backing storage for a type T,
// but instead of giving the member the proper alignas, the struct got it.
// The compiler doesn't like that. --> Suppress the warning.
#pragma warning(push)
#pragma warning(disable: 4324) // structure was padded due to alignment specifier
#include <wrl.h>
#pragma warning(pop)

#endif //WIN_TOAST_WINDOWS_WRL_COMPAT_H_

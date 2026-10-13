#pragma once
#include <cstdint>
using HWND = void*;
using HMONITOR = void*;
using HMODULE = void*;
using UINT = unsigned int;
using WPARAM = uintptr_t;
using LPARAM = intptr_t;
using LRESULT = intptr_t;
using FARPROC = intptr_t (*)();
HMODULE GetModuleHandleW(const wchar_t*);
FARPROC GetProcAddress(HMODULE, const char*);

constexpr int SW_HIDE = 0;
int ShowWindow(HWND, int);

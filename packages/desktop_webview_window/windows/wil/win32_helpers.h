//*********************************************************
//
//    Copyright (c) Microsoft. All rights reserved.
//    This code is licensed under the MIT License.
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
//    ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
//    TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//    PARTICULAR PURPOSE AND NONINFRINGEMENT.
//
//*********************************************************
#ifndef __WIL_WIN32_HELPERS_INCLUDED
#define __WIL_WIN32_HELPERS_INCLUDED

#include <minwindef.h> // FILETIME, HINSTANCE
#include <sysinfoapi.h> // GetSystemTimeAsFileTime
#include <libloaderapi.h> // GetProcAddress
#include <Psapi.h> // GetModuleFileNameExW (macro), K32GetModuleFileNameExW
#include <PathCch.h>
#include <objbase.h>

#include "result.h"
#include "resource.h"
#include "wistd_functional.h"
#include "wistd_type_traits.h"

namespace wil
{
    //! Strictly a function of the file system but this is the value for all known file system, NTFS, FAT.
    //! CDFs has a limit of 254.
    size_t const max_path_segment_length = 255;

    //! Character length not including the null, MAX_PATH (260) includes the null.
    size_t const max_path_length = 259;

    //! 32743 Character length not including the null. This is a system defined limit.
    //! The 24 is for the expansion of the roots from "C:" to "\Device\HarddiskVolume4"
    //! It will be 25 when there are more than 9 disks.
    size_t const max_extended_path_length = 0x7FFF - 24;

    //! For {guid} string form. Includes space for the null terminator.
    size_t const guid_string_buffer_length = 39;

    //! For {guid} string form. Not including the null terminator.
    size_t const guid_string_length = 38;

#pragma region FILETIME helpers
    // FILETIME duration values. FILETIME is in 100 nanosecond units.
    namespace filetime_duration
    {
        long long const one_millisecond = 10000LL;
        long long const one_second      = 10000000LL;
        long long const one_minute      = 10000000LL * 60;           // 600000000    or 600000000LL
        long long const one_hour        = 10000000LL * 60 * 60;      // 36000000000  or 36000000000LL
        long long const one_day         = 10000000LL * 60 * 60 * 24; // 864000000000 or 864000000000LL
    };

    namespace filetime
    {
        inline unsigned long long to_int64(const FILETIME &ft)
        {
            // Cannot reinterpret_cast FILETIME* to unsigned long long*
            // due to alignment differences.
            return (static_cast<unsigned long long>(ft.dwHighDateTime) << 32) + ft.dwLowDateTime;
        }

        inline FILETIME from_int64(unsigned long long i64)
        {
            static_assert(sizeof(i64) == sizeof(FILETIME), "sizes don't match");
            static_assert(__alignof(unsigned long long) >= __alignof(FILETIME), "alignment not compatible with type pun");
            return *reinterpret_cast<FILETIME *>(&i64);
        }

        inline FILETIME add(_In_ FILETIME const &ft, long long delta)
        {
            return from_int64(to_int64(ft) + delta);
        }

        inline bool is_empty(const FILETIME &ft)
        {
            return (ft.dwHighDateTime == 0) && (ft.dwLowDateTime == 0);
        }

        inline FILETIME get_system_time()
        {
            FILETIME ft;
            GetSystemTimeAsFileTime(&ft);
            return ft;
        }
    }
#pragma endregion

    // Use to adapt Win32 APIs that take a fixed size buffer into forms that return
    // an allocated buffer. Supports many types of string representation.
    // See comments below on the expected behavior of the callback.
    // Adjust stackBufferLength based on typical result sizes to optimize use and
    // to test the boundary cases.
    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT AdaptFixedSizeToAllocatedResult(string_type& result, wistd::function<HRESULT(PWSTR, size_t, size_t*)> callback)
    {
        details::string_maker<string_type> maker;

        wchar_t value[stackBufferLength];
        value[0] = L'\0';
        size_t valueLengthNeededWithNull{}; // callback returns the number of characters needed including the null terminator.
        RETURN_IF_FAILED_EXPECTED(callback(value, ARRAYSIZE(value), &valueLengthNeededWithNull));
        WI_ASSERT(valueLengthNeededWithNull > 0);
        if (valueLengthNeededWithNull <= ARRAYSIZE(value))
        {
            // Success case as described above, make() adds the space for the null.
            RETURN_IF_FAILED(maker.make(value, valueLengthNeededWithNull - 1));
        }
        else
        {
            // Did not fit in the stack allocated buffer, need to do 2 phase construction.
            // valueLengthNeededWithNull includes the null so subtract that as make() will add space for it.
            RETURN_IF_FAILED(maker.make(nullptr, valueLengthNeededWithNull - 1));

            size_t secondLength{};
            RETURN_IF_FAILED(callback(maker.buffer(), valueLengthNeededWithNull, &secondLength));

            // Ensure callback produces consistent result.
            FAIL_FAST_IF(valueLengthNeededWithNull != secondLength);
        }
        result = maker.release();
        return S_OK;
    }

    /** Expands the '%' quoted environment variables in 'input' using ExpandEnvironmentStringsW(); */
    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT ExpandEnvironmentStringsW(_In_ PCWSTR input, string_type& result) WI_NOEXCEPT
    {
        return wil::AdaptFixedSizeToAllocatedResult<string_type, stackBufferLength>(result,
            [&](_Out_writes_(valueLength) PWSTR value, size_t valueLength, _Out_ size_t* valueLengthNeededWithNul) -> HRESULT
        {
            *valueLengthNeededWithNul = ::ExpandEnvironmentStringsW(input, value, static_cast<DWORD>(valueLength));
            RETURN_LAST_ERROR_IF(*valueLengthNeededWithNul == 0);
            return S_OK;
        });
    }

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP | WINAPI_PARTITION_SYSTEM | WINAPI_PARTITION_GAMES)
    /** Searches for a specified file in a specified path using ExpandEnvironmentStringsW(); */
    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT SearchPathW(_In_opt_ PCWSTR path, _In_ PCWSTR fileName, _In_opt_ PCWSTR extension, string_type& result) WI_NOEXCEPT
    {
        return wil::AdaptFixedSizeToAllocatedResult<string_type, stackBufferLength>(result,
            [&](_Out_writes_(valueLength) PWSTR value, size_t valueLength, _Out_ size_t* valueLengthNeededWithNul) -> HRESULT
        {
            *valueLengthNeededWithNul = ::SearchPathW(path, fileName, extension, static_cast<DWORD>(valueLength), value, nullptr);

            if (*valueLengthNeededWithNul == 0)
            {
                // ERROR_FILE_NOT_FOUND is an expected return value for SearchPathW
                const HRESULT searchResult = HRESULT_FROM_WIN32(::GetLastError());
                RETURN_HR_IF_EXPECTED(searchResult, searchResult == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND));
                RETURN_IF_FAILED(searchResult);
            }

            // AdaptFixedSizeToAllocatedResult expects that the length will always include the NUL.
            // If the result is copied to the buffer, SearchPathW returns the length of copied string, WITHOUT the NUL.
            // If the buffer is too small to hold the result, SearchPathW returns the length of the required buffer WITH the nul.
            if (*valueLengthNeededWithNul < valueLength)
            {
                (*valueLengthNeededWithNul)++; // It fit, account for the null.
            }
            return S_OK;
        });
    }

    // This function does not work beyond the default stack buffer size (255).
    // Needs to to retry in a loop similar to wil::GetModuleFileNameExW
    // These updates and unit tests are tracked by https://github.com/Microsoft/wil/issues/3
    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT QueryFullProcessImageNameW(HANDLE processHandle, _In_ DWORD flags, string_type& result) WI_NOEXCEPT
    {
        return wil::AdaptFixedSizeToAllocatedResult<string_type, stackBufferLength>(result,
            [&](_Out_writes_(valueLength) PWSTR value, size_t valueLength, _Out_ size_t* valueLengthNeededWithNul) -> HRESULT
        {
            DWORD lengthToUse = static_cast<DWORD>(valueLength);
            BOOL const success = ::QueryFullProcessImageNameW(processHandle, flags, value, &lengthToUse);
            RETURN_LAST_ERROR_IF((success == FALSE) && (::GetLastError() != ERROR_INSUFFICIENT_BUFFER));
            // On both success or insufficient buffer case, add +1 for the null-terminating character
            *valueLengthNeededWithNul = lengthToUse + 1;
            return S_OK;
        });
    }

    /** Expands environment strings and checks path existence with SearchPathW */
    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT ExpandEnvAndSearchPath(_In_ PCWSTR input, string_type& result) WI_NOEXCEPT
    {
        wil::unique_cotaskmem_string expandedName;
        RETURN_IF_FAILED((wil::ExpandEnvironmentStringsW<string_type, stackBufferLength>(input, expandedName)));

        // ERROR_FILE_NOT_FOUND is an expected return value for SearchPathW
        const HRESULT searchResult = (wil::SearchPathW<string_type, stackBufferLength>(nullptr, expandedName.get(), nullptr, result));
        RETURN_HR_IF_EXPECTED(searchResult, searchResult == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND));
        RETURN_IF_FAILED(searchResult);

        return S_OK;
    }
#endif

    /** Looks up the environment variable 'key' and fails if it is not found.
    'key' should not have '%' prefix and suffix.
    Dangerous since environment variable generally are optional. */
    template <typename string_type>
    inline HRESULT GetEnvironmentVariableW(_In_ PCWSTR key, string_type& result) WI_NOEXCEPT
    {
        return wil::AdaptFixedSizeToAllocatedResult(result,
            [&](_Out_writes_(valueLength) PWSTR value, size_t valueLength, _Out_ size_t* valueLengthNeededWithNul) -> HRESULT
        {
            // If the function succeeds, the return value is the number of characters stored in the buffer
            // pointed to by lpBuffer, not including the terminating null character.
            //
            // If lpBuffer is not large enough to hold the data, the return value is the buffer size, in
            // characters, required to hold the string and its terminating null character and the contents of
            // lpBuffer are undefined.
            //
            // If the function fails, the return value is zero. If the specified environment variable was not
            // found in the environment block, GetLastError returns ERROR_ENVVAR_NOT_FOUND.

            ::SetLastError(ERROR_SUCCESS);

            *valueLengthNeededWithNul = ::GetEnvironmentVariableW(key, value, static_cast<DWORD>(valueLength));
            RETURN_LAST_ERROR_IF_EXPECTED((*valueLengthNeededWithNul == 0) && (::GetLastError() != ERROR_SUCCESS));
            if (*valueLengthNeededWithNul < valueLength)
            {
                (*valueLengthNeededWithNul)++; // It fit, account for the null.
            }
            return S_OK;
        });
    }

    /** Looks up the environment variable 'key' and returns null if it is not found.
    'key' should not have '%' prefix and suffix. */
    template <typename string_type>
    HRESULT TryGetEnvironmentVariableW(_In_ PCWSTR key, string_type& result) WI_NOEXCEPT
    {
        const auto hr = wil::GetEnvironmentVariableW<string_type>(key, result);
        RETURN_HR_IF(hr, FAILED(hr) && (hr != HRESULT_FROM_WIN32(ERROR_ENVVAR_NOT_FOUND)));
        return S_OK;
    }

    /** Retrieves the fully qualified path for the file containing the specified module loaded
    by a given process. Note GetModuleFileNameExW is a macro.*/
    template <typename string_type, size_t initialBufferLength = 128>
    HRESULT GetModuleFileNameExW(_In_opt_ HANDLE process, _In_opt_ HMODULE module, string_type& path)
    {
        // initialBufferLength is a template parameter to allow for testing.  It creates some waste for
        // shorter paths, but avoids iteration through the loop in common cases where paths are less
        // than 128 characters.
        // wil::max_extended_path_length + 1 (for the null char)
        // + 1 (to be certain GetModuleFileNameExW didn't truncate)
        size_t const ensureNoTrucation = (process != nullptr) ? 1 : 0;
        size_t const maxExtendedPathLengthWithNull = wil::max_extended_path_length + 1 + ensureNoTrucation;

        details::string_maker<string_type> maker;

        for (size_t lengthWithNull = initialBufferLength;
             lengthWithNull <= maxExtendedPathLengthWithNull;
             lengthWithNull = (wistd::min)(lengthWithNull * 2, maxExtendedPathLengthWithNull))
        {
            // make() adds space for the trailing null
            RETURN_IF_FAILED(maker.make(nullptr, lengthWithNull - 1));

            DWORD copiedCount;
            bool copyFailed;
            bool copySucceededWithNoTruncation;

            if (process != nullptr)
            {
                // GetModuleFileNameExW truncates and provides no error or other indication it has done so.
                // The only way to be sure it didn't truncate is if it didn't need the whole buffer.
                copiedCount = ::GetModuleFileNameExW(process, module, maker.buffer(), static_cast<DWORD>(lengthWithNull));
                copyFailed = (0 == copiedCount);
                copySucceededWithNoTruncation = !copyFailed && (copiedCount < lengthWithNull - 1);
            }
            else
            {
                // In cases of insufficient buffer, GetModuleFileNameW will return a value equal to lengthWithNull
                // and set the last error to ERROR_INSUFFICIENT_BUFFER.
                copiedCount = ::GetModuleFileNameW(module, maker.buffer(), static_cast<DWORD>(lengthWithNull));
                copyFailed = (0 == copiedCount);
                copySucceededWithNoTruncation = !copyFailed && (copiedCount < lengthWithNull);
            }

            if (copyFailed)
            {
                RETURN_LAST_ERROR();
            }
            else if (copySucceededWithNoTruncation)
            {
                path = maker.release();
                return S_OK;
            }

            WI_ASSERT((process != nullptr) || (::GetLastError() == ERROR_INSUFFICIENT_BUFFER));

            if (lengthWithNull == maxExtendedPathLengthWithNull)
            {
                // If we've reached this point, there's no point in trying a larger buffer size.
                break;
            }
        }

        // Any path should fit into the maximum max_extended_path_length. If we reached here, something went
        // terribly wrong.
        FAIL_FAST();
    }

    /** Retrieves the fully qualified path for the file that contains the specified module.
    The module must have been loaded by the current process. The path returned will use the
    same format that was specified when the module was loaded. Therefore, the path can be a
    long or short file name, and can have the prefix '\\?\'. */
    template <typename string_type, size_t initialBufferLength = 128>
    HRESULT GetModuleFileNameW(HMODULE module, string_type& path)
    {
        return wil::GetModuleFileNameExW<string_type, initialBufferLength>(nullptr, module, path);
    }

    template <typename string_type, size_t stackBufferLength = 256>
    HRESULT GetSystemDirectoryW(string_type& result) WI_NOEXCEPT
    {
        return wil::AdaptFixedSizeToAllocatedResult<string_type, stackBufferLength>(result,
            [&](_Out_writes_(valueLength) PWSTR value, size_t valueLength, _Out_ size_t* valueLengthNeededWithNul) -> HRESULT
        {
            *valueLengthNeededWithNul = ::GetSystemDirectoryW(value, static_cast<DWORD>(valueLength));
            RETURN_LAST_ERROR_IF(*valueLengthNeededWithNul == 0);
            if (*valueLengthNeededWithNul < valueLength)
            {
                (*valueLengthNeededWithNul)++; // it fit, account for the null
            }
            return S_OK;
        });
    }

#ifdef WIL_ENABLE_EXCEPTIONS
    /** Expands the '%' quoted environment variables in 'input' using ExpandEnvironmentStringsW(); */
    template <typename string_type = wil::unique_cotaskmem_string, size_t stackBufferLength = 256>
    string_type ExpandEnvironmentStringsW(_In_ PCWSTR input)
    {
        string_type result;
        THROW_IF_FAILED((wil::ExpandEnvironmentStringsW<string_type, stackBufferLength>(input, result)));
        return result;
    }

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP | WINAPI_PARTITION_SYSTEM | WINAPI_PARTITION_GAMES)
    /** Searches for a specified file in a specified path using SearchPathW*/
    template <typename string_type = wil::unique_cotaskmem_string, size_t stackBufferLength = 256>
    string_type TrySearchPathW(_In_opt_ PCWSTR path, _In_ PCWSTR fileName, PCWSTR _In_opt_ extension)
    {
        string_type result;
        HRESULT searchHR = wil::SearchPathW<string_type, stackBufferLength>(path, fileName, extension, result);
        THROW_HR_IF(searchHR, FAILED(searchHR) && (searchHR != HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)));
        return result;
    }
#endif

    /** Looks up the environment variable 'key' and fails if it is not found.
    'key' should not have '%' prefix and suffix.
    Dangerous since environment variable generally are optional. */
    template <typename string_type = wil::unique_cotaskmem_string>
    string_type GetEnvironmentVariableW(_In_ PCWSTR key)
    {
        string_type result;
        THROW_IF_FAILED(wil::GetEnvironmentVariableW<string_type>(key, result));
        return result;
    }

    /** Looks up the environment variable 'key' and returns null if it is not found.
    'key' should not have '%' prefix and suffix. */
    template <typename string_type = wil::unique_cotaskmem_string>
    string_type TryGetEnvironmentVariableW(_In_ PCWSTR key)
    {
        string_type result;
        THROW_IF_FAILED(wil::TryGetEnvironmentVariableW<string_type>(key, result));
        return result;
    }

    template <typename string_type = wil::unique_cotaskmem_string>
    string_type GetModuleFileNameW(HMODULE module)
    {
        string_type result;
        THROW_IF_FAILED(wil::GetModuleFileNameW(module, result));
        return result;
    }

    template <typename string_type = wil::unique_cotaskmem_string>
    string_type GetModuleFileNameExW(HANDLE process, HMODULE module)
    {
        string_type result;
        THROW_IF_FAILED(wil::GetModuleFileNameExW(process, module, result));
        return result;
    }

#endif

    /** Retrieve the HINSTANCE for the current DLL or EXE using this symbol that
    the linker provides for every module. This avoids the need for a global HINSTANCE variable
    and provides access to this value for static libraries. */
    EXTERN_C IMAGE_DOS_HEADER __ImageBase;
    inline HINSTANCE GetModuleInstanceHandle() { return reinterpret_cast<HINSTANCE>(&__ImageBase); }

    /// @cond
    namespace details
    {
        class init_once_completer
        {
            INIT_ONCE& m_once;
            unsigned long m_flags = INIT_ONCE_INIT_FAILED;
        public:
            init_once_completer(_In_ INIT_ONCE& once) : m_once(once)
            {
            }

            #pragma warning(push)
            #pragma warning(disable:4702) // https://github.com/Microsoft/wil/issues/2
            void success()
            {
                m_flags = 0;
            }
            #pragma warning(pop)

            ~init_once_completer()
            {
                ::InitOnceComplete(&m_once, m_flags, nullptr);
            }
        };
    }
    /// @endcond

    /** Performs one-time initialization
    Simplifies using the Win32 INIT_ONCE structure to perform one-time initialization. The provided `func` is invoked
    at most once.
    ~~~~
    INIT_ONCE g_init{};
    ComPtr<IFoo> g_foo;
    HRESULT MyMethod()
    {
        bool winner = false;
        RETURN_IF_FAILED(wil::init_once_nothrow(g_init, []
        {
            ComPtr<IFoo> foo;
            RETURN_IF_FAILED(::CoCreateInstance(..., IID_PPV_ARGS(&foo));
            RETURN_IF_FAILED(foo->Startup());
            g_foo = foo;
        }, &winner);
        if (winner)
        {
            RETURN_IF_FAILED(g_foo->Another());
        }
        return S_OK;
    }
    ~~~~
    See MSDN for more information on `InitOnceExecuteOnce`.
    @param initOnce The INIT_ONCE structure to use as context for initialization.
    @param func A function that will be invoked to perform initialization. If this fails, the init call
            fails and the once-init is not marked as initialized. A later caller could attempt to
            initialize it a second time.
    @param callerCompleted Set to 'true' if this was the call that caused initialization, false otherwise.
    */
    template<typename T> HRESULT init_once_nothrow(_Inout_ INIT_ONCE& initOnce, T func, _Out_opt_ bool* callerCompleted = nullptr) WI_NOEXCEPT
    {
        BOOL pending = FALSE;
        wil::assign_to_opt_param(callerCompleted, false);

        __WIL_PRIVATE_RETURN_IF_WIN32_BOOL_FALSE(InitOnceBeginInitialize(&initOnce, 0, &pending, nullptr));

        if (pending)
        {
            details::init_once_completer completion(initOnce);
            __WIL_PRIVATE_RETURN_IF_FAILED(func());
            completion.success();
            wil::assign_to_opt_param(callerCompleted, true);
        }

        return S_OK;
    }

    //! Similar to init_once_nothrow, but fails-fast if the initialization step failed. The 'callerComplete' value is
    //! returned to the caller instead of being an out-parameter.
    template<typename T> bool init_once_failfast(_Inout_  INIT_ONCE& initOnce, T&& func) WI_NOEXCEPT
    {
        bool callerCompleted;

        FAIL_FAST_IF_FAILED(init_once_nothrow(initOnce, wistd::forward<T>(func), &callerCompleted));

        return callerCompleted;
    };

    //! Returns 'true' if this `init_once` structure has finished initialization, false otherwise.
    inline bool init_once_initialized(_Inout_  INIT_ONCE& initOnce) WI_NOEXCEPT
    {
        BOOL pending = FALSE;
        return ::InitOnceBeginInitialize(&initOnce, INIT_ONCE_CHECK_ONLY, &pending, nullptr) && !pending;
    }

#ifdef WIL_ENABLE_EXCEPTIONS
    /** Performs one-time initialization
    Simplifies using the Win32 INIT_ONCE structure to perform one-time initialization. The provided `func` is invoked
    at most once.
    ~~~~
    INIT_ONCE g_init{};
    ComPtr<IFoo> g_foo;
    void MyMethod()
    {
        bool winner = wil::init_once(g_init, []
        {
            ComPtr<IFoo> foo;
            THROW_IF_FAILED(::CoCreateInstance(..., IID_PPV_ARGS(&foo));
            THROW_IF_FAILED(foo->Startup());
            g_foo = foo;
        });
        if (winner)
        {
            THROW_IF_FAILED(g_foo->Another());
        }
    }
    ~~~~
    See MSDN for more information on `InitOnceExecuteOnce`.
    @param initOnce The INIT_ONCE structure to use as context for initialization.
    @param func A function that will be invoked to perform initialization. If this fails, the init call
            fails and the once-init is not marked as initialized. A later caller could attempt to
            initialize it a second time.
    @returns 'true' if this was the call that caused initialization, false otherwise.
    */
    template<typename T> bool init_once(_Inout_  INIT_ONCE& initOnce, T func)
    {
        BOOL pending = FALSE;

        THROW_IF_WIN32_BOOL_FALSE(::InitOnceBeginInitialize(&initOnce, 0, &pending, nullptr));

        if (pending)
        {
            details::init_once_completer completion(initOnce);
            func();
            completion.success();
            return true;
        }
        else
        {
            return false;
        }
    }
#endif // WIL_ENABLE_EXCEPTIONS
}

// Macro for calling GetProcAddress(), with type safety for C++ clients
// using the type information from the specified function.
// The return value is automatically cast to match the function prototype of the input function.
//
// Sample usage:
//
// auto sendMail = GetProcAddressByFunctionDeclaration(hinstMAPI, MAPISendMailW);
// if (sendMail)
// {
//    sendMail(0, 0, pmm, MAPI_USE_DEFAULT, 0);
// }
//  Declaration
#define GetProcAddressByFunctionDeclaration(hinst, fn) reinterpret_cast<decltype(::fn)*>(GetProcAddress(hinst, #fn))

#endif // __WIL_WIN32_HELPERS_INCLUDED

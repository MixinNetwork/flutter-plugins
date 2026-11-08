#include "breakpad_client/breakpad_client.h"

#include <cstring>
#include <filesystem>
#include <iostream>
#include <sstream>

#ifdef _WIN32

#include <combaseapi.h>

#include "client/windows/handler/exception_handler.h"

#else
#include "client/linux/handler/exception_handler.h"
#include "client/linux/handler/minidump_descriptor.h"
#endif


CustomLogger g_logger;


// The Dart listener runs asynchronously, so it receives an owned copy that it
// releases with package:ffi's malloc (CoTaskMemFree on Windows, free elsewhere).
static char *copy_log(const char *log) {
    const size_t size = std::strlen(log) + 1;
#ifdef _WIN32
    auto copy = static_cast<char *>(CoTaskMemAlloc(size));
#else
    auto copy = static_cast<char *>(malloc(size));
#endif
    if (copy != nullptr) {
        std::memcpy(copy, log, size);
    }
    return copy;
}

void print_log(const char *log) {
    if (g_logger != nullptr) {
        if (auto copy = copy_log(log)) {
            g_logger(copy);
        }
    }
    std::cout << log << std::endl;
}

#ifdef _WIN32

std::wstring s2ws(const std::string &str) {
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int) str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int) str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

std::string ws2s(const wchar_t *str) {
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, str, -1, NULL, 0, NULL, NULL);
    if (size_needed <= 0) {
        return {};
    }
    std::string strTo(size_needed - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, str, -1, &strTo[0], size_needed, NULL, NULL);
    return strTo;
}


static bool dump_callback(const wchar_t *dump_path,
                          const wchar_t *minidump_id,
                          void *context,
                          EXCEPTION_POINTERS *exinfo,
                          MDRawAssertionInfo *assertion,
                          bool succeed) {
    std::ostringstream stream;
    stream << "crash dump to: " << ws2s(dump_path) << ", mini dump id: " << ws2s(minidump_id) << ", " << succeed;
    // The crashing process cannot deliver messages to the Dart logger.
    std::cerr << stream.str() << std::endl;
    return succeed;
}


#else

static bool dump_callback(const google_breakpad::MinidumpDescriptor &descriptor, void *context, bool succeed) {
    std::ostringstream stream;
    stream << "crash dump to: " << descriptor.path() << ", " << succeed;
    // The crashing process cannot deliver messages to the Dart logger.
    std::cerr << stream.str() << std::endl;
    return succeed;
}

#endif

FFI_PLUGIN_EXPORT void breakpad_client_set_logger(const CustomLogger logger) {
    g_logger = logger;
}

google_breakpad::ExceptionHandler *g_exception_handler;

FFI_PLUGIN_EXPORT int breakpad_client_init_exception_handler(const char *dir) {
#ifdef _WIN32
    // Dart passes UTF-8; a narrow std::filesystem::path uses the ANSI code page on Windows.
    const std::filesystem::path path(s2ws(dir));
#else
    const std::filesystem::path path(dir);
#endif
    std::error_code error;
    std::filesystem::create_directories(path, error);
    if (!std::filesystem::is_directory(path, error)) {
        print_log("failed to init_breakpad_exception_handler: not a directory");
        return -1;
    }

    delete (g_exception_handler);

#ifdef _WIN32
    const auto handler = new google_breakpad::ExceptionHandler(
            path.wstring(), nullptr, dump_callback,
            nullptr, google_breakpad::ExceptionHandler::HANDLER_ALL);
#else
    const google_breakpad::MinidumpDescriptor descriptor(dir);
    const auto handler = new google_breakpad::ExceptionHandler(
        descriptor, nullptr, dump_callback, nullptr, true, -1);
#endif
    g_exception_handler = handler;
    print_log("init_breakpad_exception_handler: ");
    print_log(dir);
    return 0;
}

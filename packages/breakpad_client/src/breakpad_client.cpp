#include "breakpad_client/breakpad_client.h"

#include <filesystem>
#include <iostream>
#include <sstream>
#include <locale>

#ifdef _WIN32

#include "client/windows/handler/exception_handler.h"

#else
#include "client/linux/handler/exception_handler.h"
#include "client/linux/handler/minidump_descriptor.h"
#endif


CustomLogger g_logger;


void print_log(const char *log) {
    if (g_logger != nullptr) {
        g_logger(log);
    } else {
        std::cout << log << std::endl;
    }
}

#ifdef _WIN32

std::wstring s2ws(const std::string &str) {
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int) str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int) str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}


static bool dump_callback(const wchar_t *dump_path,
                          const wchar_t *minidump_id,
                          void *context,
                          EXCEPTION_POINTERS *exinfo,
                          MDRawAssertionInfo *assertion,
                          bool succeed) {
    std::ostringstream stream;
    stream << "crash dump to: " << dump_path << "mini dump id: " << minidump_id << ", " << succeed;
    print_log(stream.str().c_str());
    return succeed;
}


#elif

static bool dump_callback(const google_breakpad::MinidumpDescriptor &descriptor, void *context, bool succeed) {
    std::ostringstream stream;
    stream << "crash dump to: " << descriptor.directory() << ", " << succeed;
    print_log(stream.str().c_str());
    return succeed;
}

#endif

FFI_PLUGIN_EXPORT void breakpad_client_set_logger(const CustomLogger logger) {
    g_logger = logger;
}

google_breakpad::ExceptionHandler *g_exception_handler;

FFI_PLUGIN_EXPORT int breakpad_client_init_exception_handler(const char *dir) {
    if (!std::filesystem::exists(dir) && !std::filesystem::create_directories(dir)) {
        print_log("failed to init_breakpad_exception_handler: create dir failed");
    }
    if (!std::filesystem::is_directory(dir)) {
        print_log("failed to init_breakpad_exception_handler: not a directory");
        return -1;
    }
    std::filesystem::create_directories(dir);

    delete (g_exception_handler);

#ifdef _WIN32
    auto dump_path = s2ws(dir);
    const auto handler = new google_breakpad::ExceptionHandler(
            dump_path, nullptr, dump_callback,
            nullptr, google_breakpad::ExceptionHandler::HANDLER_ALL);
#elif
    const google_breakpad::MinidumpDescriptor descriptor(dir);
    const auto handler = new google_breakpad::ExceptionHandler(
            descriptor, nullptr, dump_callback, nullptr, true, -1);
#endif
    g_exception_handler = handler;
    print_log("init_breakpad_exception_handler: ");
    print_log(dir);
    return 0;
}

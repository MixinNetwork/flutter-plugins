#include "breakpad_client/breakpad_client.h"

#include <filesystem>
#include <iostream>

#include "client/linux/handler/exception_handler.h"
#include "client/linux/handler/minidump_descriptor.h"


CustomLogger g_logger;


void print_log(const char *log) {
    if (g_logger != nullptr) {
        g_logger(log);
    } else {
        std::cout << log << std::endl;
    }
}


static bool dump_callback(const google_breakpad::MinidumpDescriptor &descriptor, void *context, bool succeed) {
    std::ostringstream stream;
    stream << "crash dump to: " << descriptor.directory() << ", " << succeed;
    print_log(stream.str().c_str());
    return succeed;
}

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

    delete(g_exception_handler);

    const google_breakpad::MinidumpDescriptor descriptor(dir);
    const auto handler = new google_breakpad::ExceptionHandler(
        descriptor, nullptr, dump_callback, nullptr, true, -1);
    g_exception_handler = handler;
    print_log("init_breakpad_exception_handler: ");
    print_log(dir);
    return 0;
}

#include "breakpad_client/breakpad_client.h"

#include <filesystem>
#include <iostream>

#include "client/linux/handler/exception_handler.h"
#include "client/linux/handler/minidump_descriptor.h"


static bool dump_callback(const google_breakpad::MinidumpDescriptor &descriptor, void *context, bool succeed) {
    std::cout << "crash dump to: " << descriptor.directory() << ", " << succeed << std::endl;
    return succeed;
}


FFI_PLUGIN_EXPORT void init_breakpad_exception_handler(const char *dir) {
    if (!std::filesystem::exists(dir) && !std::filesystem::create_directories(dir)) {
        std::cout << "failed to init_breakpad_exception_handler: create dir failed" << std::endl;
    }
    if (!std::filesystem::is_directory(dir)) {
        std::cout << "failed to init_breakpad_exception_handler: not a directory" << std::endl;
        return;
    }
    std::filesystem::create_directories(dir);
    const google_breakpad::MinidumpDescriptor descriptor(dir);
    static google_breakpad::ExceptionHandler handler(descriptor, nullptr, dump_callback, nullptr, true, -1);
    std::cout << "init_breakpad_exception_handler: " << dir << std::endl;
    handler.set_minidump_descriptor(descriptor);
}

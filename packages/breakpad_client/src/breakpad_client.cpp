#include "breakpad_client.h"

#include <iostream>

#include "client/linux/handler/exception_handler.h"
#include "client/linux/handler/minidump_descriptor.h"


static bool dump_callback(const google_breakpad::MinidumpDescriptor &descriptor, void *context, bool succeed) {
    std::cout << "crash dump to: " << descriptor.directory() << ", " << succeed << std::endl;
    return succeed;
}


// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT void init_breakpad_exception_handler(const char* dir) {
    const google_breakpad::MinidumpDescriptor descriptor(dir);
    static google_breakpad::ExceptionHandler handler(descriptor, nullptr, dump_callback, nullptr, true, -1);
    std::cout << "init_breakpad_exception_handler: " << dir << std::endl;
    handler.set_minidump_descriptor(descriptor);
}


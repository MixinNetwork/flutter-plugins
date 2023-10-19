#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else

#include <pthread.h>
#include <unistd.h>

#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

FFI_PLUGIN_EXPORT intptr_t
mixin_logger_init(const char *dir, intptr_t max_file_size, intptr_t max_file_count, const char *file_leading);

FFI_PLUGIN_EXPORT intptr_t mixin_logger_set_file_leading(const char *file_leading);

FFI_PLUGIN_EXPORT intptr_t mixin_logger_write_log(const char *log);
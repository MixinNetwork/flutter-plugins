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

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*CustomLogger)(const char *str);

FFI_PLUGIN_EXPORT void breakpad_client_set_logger(CustomLogger logger);

FFI_PLUGIN_EXPORT int breakpad_client_init_exception_handler(const char *dir);

#ifdef __cplusplus
}
#endif

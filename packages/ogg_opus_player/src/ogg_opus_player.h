#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT extern "C"
#endif

FFI_PLUGIN_EXPORT void *ogg_opus_player_create(const char *file_path);

FFI_PLUGIN_EXPORT void ogg_opus_player_pause(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_play(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_dispose(void *player);
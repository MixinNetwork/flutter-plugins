#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

FFI_PLUGIN_EXPORT void *ogg_opus_player_create(const char *file_path);

FFI_PLUGIN_EXPORT void ogg_opus_player_pause(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_play(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_dispose(void *player);

FFI_PLUGIN_EXPORT double ogg_opus_player_get_current_time(void *player);

#ifdef __cplusplus
}
#endif
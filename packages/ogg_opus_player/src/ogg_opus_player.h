#if _WIN32
#include <Windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#include "stdint.h"

#ifdef __cplusplus
extern "C" {
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

FFI_PLUGIN_EXPORT void *ogg_opus_player_create(const char *file_path, int64_t send_port);

FFI_PLUGIN_EXPORT void ogg_opus_player_pause(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_play(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_dispose(void *player);

FFI_PLUGIN_EXPORT double ogg_opus_player_get_current_time(void *player);

FFI_PLUGIN_EXPORT void ogg_opus_player_set_playback_rate(void *player, double rate);

FFI_PLUGIN_EXPORT void ogg_opus_player_initialize_dart(void *native_port);

#ifdef __cplusplus
}
#endif
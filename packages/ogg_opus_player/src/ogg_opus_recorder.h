//
// Created by boyan01 on 2022/3/28.
//

#ifndef OGG_OPUS_PLAYER_LIBRARY__OGG_OPUS_RECORDER_H_
#define OGG_OPUS_PLAYER_LIBRARY__OGG_OPUS_RECORDER_H_

#include "stdint.h"

#ifdef __cplusplus
extern "C" {
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

FFI_PLUGIN_EXPORT void *ogg_opus_recorder_create(const char *file_path, int64_t send_port);

FFI_PLUGIN_EXPORT void ogg_opus_recorder_start(void *recoder);

FFI_PLUGIN_EXPORT void ogg_opus_recorder_stop(void *recoder);

FFI_PLUGIN_EXPORT void ogg_opus_recorder_destroy(void *recoder);

FFI_PLUGIN_EXPORT void ogg_opus_recorder_get_wave_data(void *recoder, uint8_t **wave_data, int64_t *wave_data_length);

FFI_PLUGIN_EXPORT double ogg_opus_recorder_get_duration(void *recoder);

#ifdef __cplusplus
}
#endif

#endif //OGG_OPUS_PLAYER_LIBRARY__OGG_OPUS_RECORDER_H_

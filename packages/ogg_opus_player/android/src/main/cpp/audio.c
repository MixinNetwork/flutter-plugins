#include <jni.h>
#include <stdio.h>
#include <opus.h>
#include <opusenc.h>
#include <stdlib.h>
#include <string.h>
#include "utils.h"

OggOpusEnc *enc;
OggOpusComments *comments;
int error;

static inline void set_bits(uint8_t *bytes, int32_t bitOffset, int32_t value) {
    bytes += bitOffset / 8;
    bitOffset %= 8;
    *((int32_t *) bytes) |= (value << bitOffset);
}

JNIEXPORT jint JNICALL Java_one_mixin_oggOpusPlayer_OpusAudioRecorder_startRecord(JNIEnv *env, jclass clazz, jstring path) {
    const char *pathStr = (*env)->GetStringUTFChars(env, path, 0);
    if (!pathStr) {
        LOGE("Error path");
        return 0;
    }
    comments = ope_comments_create();
    enc = ope_encoder_create_file(pathStr, comments, 16000, 1, 0, &error);
    if (error != OPE_OK) {
        LOGE("Create OggOpusEnc failed");
        return error;
    }
    error = ope_encoder_ctl(enc, OPUS_SET_BITRATE_REQUEST, 16 * 1024);
    if (error != OPE_OK) {
        return error;
    }

    return OPE_OK;
}

JNIEXPORT jint JNICALL Java_one_mixin_oggOpusPlayer_OpusAudioRecorder_writeFrame(JNIEnv *env, jclass clazz, jshortArray frame, jint len) {
    jshort *sampleBuffer = (*env) -> GetShortArrayElements(env, frame, 0);
    int result = ope_encoder_write(enc, sampleBuffer, len);
    (*env)->ReleaseShortArrayElements(env, frame, sampleBuffer, 0);
    return result;
}

JNIEXPORT void JNICALL Java_one_mixin_oggOpusPlayer_OpusAudioRecorder_stopRecord(JNIEnv *env, jclass clazz) {
    ope_encoder_drain(enc);
    ope_encoder_destroy(enc);
    ope_comments_destroy(comments);
    LOGI("ope encoder destroy");
}

JNIEXPORT jbyteArray JNICALL Java_one_mixin_oggOpusPlayer_OpusAudioRecorder_getWaveform2(JNIEnv *env, jclass clazz, jshortArray array, jint length) {
    jshort *sampleBuffer = (*env)->GetShortArrayElements(env, array, 0);
    const int32_t resultSamples = 100;
    uint16_t *samples = malloc(100 * 2);
    uint64_t sampleIndex = 0;
    uint16_t peakSample = 0;
    int32_t sampleRate = (int32_t) max(1, length / resultSamples);
    int32_t index = 0;

    for (int32_t i = 0; i < length; i++) {
        uint16_t sample = (uint16_t) abs(sampleBuffer[i]);
        if (sample > peakSample) {
            peakSample = sample;
        }
        if (sampleIndex++ % sampleRate == 0) {
            if (index < resultSamples) {
                samples[index++] = peakSample;
            }
            peakSample = 0;
        }
    }

    int64_t sumSamples = 0;
    for (int32_t i = 0; i < resultSamples; i++) {
        sumSamples += samples[i];
    }
    uint16_t peak = (uint16_t) (sumSamples * 1.8f / resultSamples);
    if (peak < 2500) {
        peak = 2500;
    }

    for (int32_t i = 0; i < resultSamples; i++) {
        uint16_t sample = (uint16_t) ((int64_t) samples[i]);
        if (sample > peak) {
            samples[i] = peak;
        }
    }

    (*env)->ReleaseShortArrayElements(env, array, sampleBuffer, 0);

    uint32_t bitStreamLength = resultSamples * 5 / 8 + 1;
    jbyteArray result = (*env)->NewByteArray(env, bitStreamLength);
    if (result) {
        uint8_t *bytes = malloc(bitStreamLength + 4);
        memset(bytes, 0, bitStreamLength + 4);
        for (int32_t i = 0; i < resultSamples; i++) {
            int32_t value = min(31, abs((int32_t) samples[i]) * 31 / peak);
            set_bits(bytes, i * 5, value & 31);
        }
        (*env)->SetByteArrayRegion(env, result, 0, bitStreamLength, (jbyte *) bytes);
    }

    free(samples);

    return result;
}
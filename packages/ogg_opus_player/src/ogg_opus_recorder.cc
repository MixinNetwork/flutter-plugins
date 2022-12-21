//
// Created by boyan01 on 2022/3/28.
//

#include "ogg_opus_recorder.h"

#include "ogg/opusenc.h"

#include <memory>
#include <iostream>
#include <vector>
#include <cmath>
#include <cstring>

#include "SDL.h"
#include "ogg_opus_utils.h"

namespace {

inline void set_bits(uint8_t *bytes, int32_t bitOffset, int32_t value) {
  bytes += bitOffset / 8;
  bitOffset %= 8;
  *((int32_t *) bytes) |= (value << bitOffset);
}

class OggOpusWriter {

 public:
  OggOpusWriter() = default;

  int Init(const char *file_name, int sample_rate);

  int Write(const opus_int16 *data, int size);

  ~OggOpusWriter();

 private:
  OggOpusComments *comments_ = nullptr;
  OggOpusEnc *encoder_ = nullptr;

};

int OggOpusWriter::Init(const char *file_name, opus_int32 sample_rate) {
  auto *comments = ope_comments_create();
  if (!comments) {
    return -1;
  }
  int error = OPE_OK;
  auto encoder = ope_encoder_create_file(file_name, comments, sample_rate, 1, 0, &error);
  if (error != OPE_OK) {
    ope_comments_destroy(comments);
    return -1;
  }
  error = ope_encoder_ctl(encoder, OPUS_SET_BITRATE_REQUEST, 16 * 1024);
  if (error != OPE_OK) {
    ope_encoder_destroy(encoder);
    ope_comments_destroy(comments);
    return -1;
  }
  comments_ = comments;
  encoder_ = encoder;
  return 0;
}

OggOpusWriter::~OggOpusWriter() {
  if (encoder_) {
    ope_encoder_drain(encoder_);
    ope_encoder_destroy(encoder_);
  }
  if (comments_) {
    ope_comments_destroy(comments_);
  }
}

int OggOpusWriter::Write(const opus_int16 *data, int size) {
  if (!encoder_) {
    return -1;
  }
  int error = ope_encoder_write(encoder_, data, size / 2);
  return error;
}

class SdlOggOpusRecorder {

 private:
  std::unique_ptr<OggOpusWriter> writer_;
  int sample_rate_ = 0;

  SDL_AudioDeviceID device_id_ = -1;

  std::vector<int16_t> waveform_samples_;

  int16_t wave_form_peek_ = 0;
  int32_t wave_form_peek_count_ = 0;

  // recorded duration in seconds
  double duration_ = 0;

 public:
  SdlOggOpusRecorder();

  int Init(const char *file_name);

  void Start() const;

  void Stop();

  double GetDuration() const { return duration_; }

  ~SdlOggOpusRecorder();

  void WriteAudioData(Uint8 *stream, int size);

  void MakeWaveData(uint8_t **result, int64_t *size);

};

SdlOggOpusRecorder::SdlOggOpusRecorder() : waveform_samples_() {

}

int SdlOggOpusRecorder::Init(const char *file_name) {

  global_init_sdl2();

  SDL_AudioSpec wanted_spec;
  SDL_AudioSpec spec;
  wanted_spec.freq = 16000;
  wanted_spec.format = AUDIO_S16SYS;
  wanted_spec.channels = 1;
  wanted_spec.samples = 1024;
  wanted_spec.callback = [](void *userdata, Uint8 *stream, int len) {
    auto *recoder = static_cast<SdlOggOpusRecorder *>(userdata);
    recoder->WriteAudioData(stream, len);
  };
  wanted_spec.userdata = this;
  device_id_ = SDL_OpenAudioDevice(nullptr, 1, &wanted_spec, &spec,
                                   0);
  if (device_id_ <= 0) {
    return -1;
  }
  sample_rate_ = spec.freq;
  std::cout << "SDL_OpenAudioDevice: spec freq = " << spec.freq << std::endl;
  writer_ = std::make_unique<OggOpusWriter>();
  return writer_->Init(file_name, sample_rate_);
}

void SdlOggOpusRecorder::WriteAudioData(Uint8 *stream, int size) {
  if (!writer_) {
    std::cerr << "writer_ is null" << std::endl;
    return;
  }
  writer_->Write(reinterpret_cast<opus_int16 *>(stream), size);

  auto number_of_samples = size / 2;
  duration_ = duration_ + number_of_samples / 16000.0;

  // process waveform data
  if (number_of_samples <= 0) {
    return;
  }

  auto *samples = reinterpret_cast<int16_t *>(stream);
  for (int i = 0; i < number_of_samples; ++i) {
    auto sample = samples[i];
    wave_form_peek_ = std::max(wave_form_peek_, sample);
    wave_form_peek_count_++;

    if (wave_form_peek_count_ >= 100) {
      waveform_samples_.push_back(wave_form_peek_);
      wave_form_peek_ = 0;
      wave_form_peek_count_ = 0;
    }
  }

}

void SdlOggOpusRecorder::Start() const {
  SDL_PauseAudioDevice(device_id_, 0);
}

void SdlOggOpusRecorder::Stop() {
  SDL_LockAudioDevice(device_id_);
  SDL_PauseAudioDevice(device_id_, 1);
  writer_ = nullptr;
  SDL_UnlockAudioDevice(device_id_);
  SDL_CloseAudioDevice(device_id_);
  device_id_ = 0;
}

SdlOggOpusRecorder::~SdlOggOpusRecorder() {
  if (device_id_ > 0) {
    Stop();
  }
}

void SdlOggOpusRecorder::MakeWaveData(uint8_t **result, int64_t *size) {
  const int number_of_waveform_intensities = 100;
  auto *intensities = static_cast<uint8_t *>(malloc(number_of_waveform_intensities));
  memset(intensities, 0, number_of_waveform_intensities);

  int16_t min_raw_sample = INT16_MAX;
  int16_t max_raw_sample = 0;

  for (auto &sample : waveform_samples_) {
    min_raw_sample = std::min(min_raw_sample, sample);
    max_raw_sample = std::max(max_raw_sample, sample);
  }

  auto range = max_raw_sample - min_raw_sample;
  auto delta = range == 0 ? 0 : float_t(UINT8_MAX) / float_t(range);

  for (int i = 0; i < waveform_samples_.size(); ++i) {
    auto index = i * number_of_waveform_intensities / waveform_samples_.size();
    auto intensity = std::min(float_t(UINT8_MAX), float_t(waveform_samples_[i]) * delta);
    intensities[index] = uint8_t(intensity);
  }

  *result = intensities;
  *size = number_of_waveform_intensities;

}

}

void *ogg_opus_recorder_create(const char *file_path, int64_t send_port) {
  auto *recoder = new SdlOggOpusRecorder();
  if (recoder->Init(file_path) < 0) {
    delete recoder;
    return nullptr;
  }
  return recoder;
}

void ogg_opus_recorder_stop(void *recoder) {
  if (!recoder) {
    return;
  }
  auto *sdl_recoder = static_cast<SdlOggOpusRecorder *>(recoder);
  sdl_recoder->Stop();
}

void ogg_opus_recorder_start(void *recoder) {
  if (!recoder) {
    return;
  }
  auto *sdl_recoder = static_cast<SdlOggOpusRecorder *>(recoder);
  sdl_recoder->Start();
}

void ogg_opus_recorder_destroy(void *recoder) {
  if (!recoder) {
    return;
  }
  auto *sdl_recoder = static_cast<SdlOggOpusRecorder *>(recoder);
  delete sdl_recoder;
}

void ogg_opus_recorder_get_wave_data(void *recoder, uint8_t **wave_data, int64_t *wave_data_length) {
  if (!recoder) {
    return;
  }
  auto *sdl_recoder = static_cast<SdlOggOpusRecorder *>(recoder);
  sdl_recoder->MakeWaveData(wave_data, wave_data_length);
}

double ogg_opus_recorder_get_duration(void *recoder) {
  if (!recoder) {
    return 0;
  }
  auto *sdl_recoder = static_cast<SdlOggOpusRecorder *>(recoder);
  return sdl_recoder->GetDuration();
}

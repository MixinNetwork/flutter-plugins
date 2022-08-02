//
// Created by boyan01 on 2022/3/28.
//

#include "ogg_opus_recorder.h"

#include "ogg/opusenc.h"

#include <memory>
#include <iostream>

#include "SDL.h"
#include "ogg_opus_utils.h"

namespace {

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

 public:
  SdlOggOpusRecorder() = default;

  int Init(const char *file_name);

  void Start() const;

  void Stop() const;

  ~SdlOggOpusRecorder();

  void WriteAudioData(Uint8 *stream, int size);
};
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
}

void SdlOggOpusRecorder::Start() const {
  SDL_PauseAudioDevice(device_id_, 0);
}

void SdlOggOpusRecorder::Stop() const {
  SDL_PauseAudioDevice(device_id_, 1);
}

SdlOggOpusRecorder::~SdlOggOpusRecorder() {
  if (device_id_ > 0) {
    SDL_CloseAudioDevice(device_id_);
  }
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

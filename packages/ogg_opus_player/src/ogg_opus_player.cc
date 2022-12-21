#include "ogg_opus_player.h"

#include <iostream>
#include <memory>
#include <chrono>
#include <cstring>

#include "ogg/opus.h"
#include "ogg/opusfile.h"

#include "dart_api_dl.h"
#include "SDL.h"

#include "ogg_opus_utils.h"
#include "sonic.h"

//#define _OPUS_OGG_PLAYER_LOG

namespace {

class OggOpusReader {

 private:
  const char *file_path_;
  OggOpusFile *opus_file_;

  bool ended_ = false;

 public:

  explicit OggOpusReader(const char *file_path);

  ~OggOpusReader();

  int ReadPcmData(opus_int16 *data, int length);

  int GetChannelCount() const;

};

OggOpusReader::OggOpusReader(const char *file_path) : file_path_(file_path), opus_file_(nullptr) {
  int result;
  auto opus_file = op_open_file(file_path, &result);
  if (result == 0 && opus_file) {
    opus_file_ = opus_file;
  } else {
    std::cerr << "open opus file failed" << result << std::endl;
  }
}

OggOpusReader::~OggOpusReader() {
  if (opus_file_) {
    op_free(opus_file_);
  }
}
int OggOpusReader::ReadPcmData(opus_int16 *data, int length) {
  if (!opus_file_) {
    return 0;
  }
  auto read = 0;

  auto result = 1;
  while ((result == OP_HOLE || result > 0) && read < length) {
    result = op_read(opus_file_, data + read,
                     length - read, nullptr);
    if (result >= 0) {
      read += result;
    }
  }

  if (result < 0) {
    return 0;
  }

  if (result == 0) {
    ended_ = true;
  }

  return read;
}
int OggOpusReader::GetChannelCount() const {
  if (!opus_file_) {
    return 1;
  }
  return op_channel_count(opus_file_, -1);
}

class Player {
 public:
  virtual void Play() = 0;
  virtual void Pause() = 0;

  virtual ~Player();

  virtual double CurrentTime() = 0;

  virtual void SetPlaybackRate(double rate) = 0;
};

Player::~Player() = default;

enum DartPortMessage {
  PLAYER_REACH_ENDED = 0
};

class SdlOggOpusPlayer : public Player {

 public:
  SdlOggOpusPlayer(const char *file_path, Dart_Port_DL send_port);
  ~SdlOggOpusPlayer() override;

  void Play() override;
  void Pause() override;
  double CurrentTime() override;

  void SetPlaybackRate(double rate) override;

 private:
  std::unique_ptr<OggOpusReader> reader_;

  SDL_AudioDeviceID audio_device_id_ = -1;

  double current_time_ = 0;

  int64_t last_update_time_ = 0;

  bool paused_ = true;

  Dart_Port_DL dart_port_dl_;

  sonicStream sonic_stream_;

  int Initialize();

  void ReadAudioData(uint16_t *stream, int len);

};

SdlOggOpusPlayer::SdlOggOpusPlayer(const char *file_path, Dart_Port_DL send_port)
    : reader_(std::make_unique<OggOpusReader>(file_path)),
      dart_port_dl_(send_port),
      sonic_stream_(nullptr) {
#ifdef _OPUS_OGG_PLAYER_LOG
  std::cout << "SdlOggOpusPlayer: " << file_path << " port: " << send_port << std::endl;
#endif
  Initialize();
}

void SdlOggOpusPlayer::Play() {
  if (audio_device_id_ > 0) {
    paused_ = false;
    SDL_PauseAudioDevice(audio_device_id_, 0);
  }
}
void SdlOggOpusPlayer::Pause() {
  if (audio_device_id_ > 0) {
    SDL_PauseAudioDevice(audio_device_id_, 1);
    paused_ = true;
    auto offset = std::chrono::system_clock::now().time_since_epoch().count() - last_update_time_;
    current_time_ += double(offset) / 1000000000.0;
    last_update_time_ = 0;
  }
}

void SdlOggOpusPlayer::ReadAudioData(uint16_t *stream, int len) {
  if (!sonic_stream_) {
    memset(stream, 0, len * sizeof(uint16_t));
    return;
  }

  auto read = 0;
  auto pcm_read = 0;
  while (read < len) {
    auto result = sonicReadShortFromStream(
        sonic_stream_, reinterpret_cast<short *>(stream + read),
        len - read
    );
    if (result > 0) {
      read += result;
    } else if (result == 0) {
      auto buffer = static_cast<opus_int16 *>(malloc(len * sizeof(opus_int16)));
      auto data = reader_->ReadPcmData(buffer, 500);
      if (data > 0) {
        sonicWriteShortToStream(sonic_stream_, buffer, data);
        pcm_read += data;
      } else {
        break;
      }
      free(buffer);
    }
  }

  current_time_ = current_time_ + pcm_read / 48000.0;
  last_update_time_ = std::chrono::system_clock::now().time_since_epoch().count();
  if (read <= 0) {
    Dart_PostInteger_DL(dart_port_dl_, PLAYER_REACH_ENDED);
  }
}

bool global_init = false;

int SdlOggOpusPlayer::Initialize() {
  global_init_sdl2();

  SDL_AudioSpec wanted_spec, spec;
  wanted_spec.silence = 0;
  wanted_spec.format = AUDIO_S16SYS;
  wanted_spec.channels = reader_->GetChannelCount();
  wanted_spec.samples = 1024;
  wanted_spec.freq = 48000;
  wanted_spec.callback = [](void *userdata, Uint8 *stream, int len) {
    auto *player = static_cast<SdlOggOpusPlayer *>(userdata);
    auto *data = reinterpret_cast<Uint16 *>(stream);
    player->ReadAudioData(data, len / 2);
  };
  wanted_spec.userdata = this;

  audio_device_id_ = SDL_OpenAudioDevice(nullptr, 0,
                                         &wanted_spec, &spec,
                                         0);
  if (audio_device_id_ <= 0) {
    std::cout << "SDL_OpenAudioDevice failed: " << SDL_GetError() << std::endl;
    return -1;
  }

  sonic_stream_ = sonicCreateStream(spec.freq, spec.channels);

  if (spec.format != AUDIO_S16SYS) {
    std::cout << "SDL_OpenAudioDevice failed: spec format" << std::endl;
    return -1;
  }

#ifdef _OPUS_OGG_PLAYER_LOG
  std::cout << "SDL_OpenAudioDevice spec: "
            << "\n  freq: " << spec.freq
            << "\n  format: " << spec.format
            << "\n  channels: " << int(spec.channels)
            << "\n  samples: " << spec.samples
            << std::endl;
#endif

  return 0;
}

SdlOggOpusPlayer::~SdlOggOpusPlayer() {
  if (audio_device_id_ > 0) {
    SDL_CloseAudioDevice(audio_device_id_);
  }
  if (sonic_stream_) {
    sonicDestroyStream(sonic_stream_);
  }
}

double SdlOggOpusPlayer::CurrentTime() {
  if (last_update_time_ == 0 || paused_) {
    return current_time_;
  }
  auto time = std::chrono::system_clock::now().time_since_epoch().count() - last_update_time_;
  auto speed = sonic_stream_ ? sonicGetSpeed(sonic_stream_) : 1.0f;
  return current_time_ + ((double) time / 1000000000.0) * speed;
}

void SdlOggOpusPlayer::SetPlaybackRate(double rate) {
  if (sonic_stream_) {
    sonicSetSpeed(sonic_stream_, float(rate));
  }
}

}

void global_init_sdl2() {
  if (!global_init) {
    SDL_InitSubSystem(SDL_INIT_AUDIO);
    global_init = true;
  }
}

void *ogg_opus_player_create(const char *file_path, Dart_Port_DL send_port) {
  auto *player = new SdlOggOpusPlayer(file_path, send_port);
  return player;
}

void ogg_opus_player_pause(void *player) {
  auto *p = static_cast<Player *>(player);
  p->Pause();
}
void ogg_opus_player_play(void *player) {
  auto *p = static_cast<Player *>(player);
  p->Play();
}

void ogg_opus_player_dispose(void *player) {
  auto *p = static_cast<Player *>(player);
  ogg_opus_player_pause(player);
  delete p;
}

double ogg_opus_player_get_current_time(void *player) {
  auto *p = static_cast<Player *>(player);
  return p->CurrentTime();
}

void ogg_opus_player_initialize_dart(void *native_port) {
  Dart_InitializeApiDL(native_port);
}

void ogg_opus_player_set_playback_rate(void *player, double rate) {
  auto *p = static_cast<Player *>(player);
  p->SetPlaybackRate(rate);
}

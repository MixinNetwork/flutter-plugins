## 0.7.0

* [iOS] support arm64 x86_64 simulator.

## 0.6.4

* [Windows] fix audio recorder sometimes makes invalid ogg file.
* [Windows] upgrade SDL2 to 2.26.1.

## 0.6.3

* [Windows] bump libopusenc to the latest version. which has the fix stream assertion on Windows.

## 0.6.2

* fix setPlaybackRate on plugin didn't wait player initialized.

## 0.6.1

* add `OggOpusPlayer.setPlaybackRate` method.

## 0.6.0

* add Android support

## 0.5.1

* [Linux] libogg_opus_player.so add link to libogg

## 0.5.0

* [Linux] break change: remove libogg and libopus shared library, use system library instead.
* [Linux] support aarch64

## 0.4.1

[Linux] replace opus static libraries to release version.

## 0.4.0

Support recording voice.

## 0.3.2

Fix wrong playback speed on some devices.

## 0.3.1

Fix linux build.

## 0.3.0

support windows and linux.

## 0.2.0

support macOS arm64

## 0.1.0

break change: upgrade iOS min version from 10.0 to 12.0

## 0.0.1

add iOS/ macOS support.

# ogg_opus_player

[![Pub](https://img.shields.io/pub/v/ogg_opus_player.svg)](https://pub.dev/packages/ogg_opus_player)

a ogg opus file player for flutter.

| platform |   | required os version |
|----------|---|---------------------|
| iOS      | ✅ | 10.0                |
| macOS    | ✅ | 10.12               |
| Windows  | ✅ |                     |
| Linux    | ✅ |                     |
| Android  | ✅ | minSdk 21           |

## Getting Started

1. add `ogg_opus_player` to your pubspec.yaml

    ```yaml
      ogg_opus_player: $latest_version
    ```

2. then you can play your opus ogg file from `OggOpusPlayer`

    ```dart
    import 'package:ogg_opus_player/ogg_opus_player.dart';
    
    void playOggOpusFile() {
      final player = OggOpusPlayer("file_path");
    
      player.play();
      player.pause();
    
      player.dipose();
    }
    ```

## AudioSession

For android/iOS platform, you need to manage audio session by yourself.

It is recommended to use [audio_session](https://pub.dev/packages/audio_session) to manage audio session.

## Linux required

Need SDL2 library installed on Linux.

```shell
sudo apt-get install libsdl2-dev
sudo apt-get install libopus-dev
```

## iOS/macOS required

Record voice need update your app's Info.plist NSMicrophoneUsageDescription key with a string value
explaining to the user how the app uses this data.

For example:

```
    <key>NSMicrophoneUsageDescription</key>
    <string>Example uses your microphone to record voice for test.</string>
```

for macOS, you also need update your `DebugProfile.entitlements` and `ReleaseProfile.entitlements` with the following:

```
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
```

## LICENSE

see LICENSE file

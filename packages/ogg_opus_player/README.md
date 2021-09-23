# ogg_opus_player

[![Pub](https://img.shields.io/pub/v/ogg_opus_player.svg)](https://pub.dev/packages/ogg_opus_player)

a ogg opus file player for flutter.

|     platform     |       |  required os version |
| -------- | ------- | ---- |
| iOS    | ✅    |  10.0 |
| macOS    | ✅     |   10.12  |

## Getting Started

1. add `ogg_opus_player` to your pubspec.yaml

```yaml
  ogg_opus_player: $latest_version
```

2. then you can play you opus ogg file from `OggOpusPlayer`

```dart

final player = OggOpusPlayer("file_path");

player.play();
player.pause();

player.dipose();

```


## LICENSE

see LICENSE file

## 0.6.0

- Android: Migrate to built-in Kotlin to resolve Flutter's Kotlin Gradle Plugin migration warning. ([#536](https://github.com/MixinNetwork/flutter-plugins/pull/536); thanks [bsutton](https://github.com/bsutton))
- Web: Handle asynchronous errors when reading clipboard HTML and images so failed reads return `null`. ([#493](https://github.com/MixinNetwork/flutter-plugins/pull/493); thanks [loucass](https://github.com/loucass))

### Breaking changes

- Require Flutter 3.44 and Dart 3.12 or later. Upgrade your Flutter SDK before updating to this release.

## 0.5.0

* add SPM Support. [@vicajilau](https://github.com/MixinNetwork/flutter-plugins/pull/463)

## 0.4.0

* introduce Android support. thanks to
  [@Seidko](https://github.com/MixinNetwork/flutter-plugins/pull/362)
  [@vicajilau](https://github.com/MixinNetwork/flutter-plugins/pull/383)

## 0.3.0

* bump web version to 1.0.0

## 0.2.0

* update docs. [@OutdatedGuy](https://github.com/OutdatedGuy)
* fix js version dependency. [@alexkmbk](https://github.com/alexkmbk)

## 0.1.1

* add `html` to get the html from clipboard. [@alexkmbk](https://github.com/alexkmbk)
* support write image on web.

## 0.1.0

* add web support.
* add `writeText` and `text` support.

## 0.0.3

* Remove `atlimage.h` include for Windows. fix [#75](https://github.com/MixinNetwork/flutter-plugins/issues/75)

## 0.0.2

* add get/write image on iOS.

## 0.0.1

* add Linux,Windows,macOS support.
* support basic functions.

# Changelog

## 0.4.1

* [macOS] improve enumerateDraggingItems on macOS.

## 0.4.0

* [Android] update to later version of kotlin(1.5.2). [#155](https://github.com/MixinNetwork/flutter-plugins/pull/155)
  by [Cal Holloway](https://github.com/CalHoll)
* [macOS] Fix broken gestures when used with modified
  MainFlutterWindow. [#162](https://github.com/MixinNetwork/flutter-plugins/pull/162)
  by [Josh Matthews](https://github.com/jmatth)

## 0.3.3

* Fix dragging multiple files at once from Apple Music does not work
  well. [#72](https://github.com/MixinNetwork/flutter-plugins/issues/72)

## 0.3.2

* Fix non ascii characters path on linux. [#53](https://github.com/MixinNetwork/flutter-plugins/issues/53)

## 0.3.1

* Fix desktop_drop web lastModifiedDate. (Thanks [Luigi Rosso](https://github.com/luigi-rosso))

## 0.3.0

** BREAK CHANGES**

* replace DropDoneDetails property `urls: List<Uri>` to `files: List<XFile>`. which is more general.

## 0.2.0

Add web support

## 0.1.2

[Linux] Fix do not work on Wayland.

## 0.1.1

update plugin description.

## 0.1.0

1. add android support. (preview)
2. expose pointer coordinates.

**BREAK CHANGE**:

1. Change `onDragEntered`,`onDragExited` and `onDragUpdated` callbacks signature from `VoidCallback`
   to `void Function(DropEventDetails)`.
2. Change `DropDoneDetails` from `void Function(List<Uri>)` to `void Function(DropDoneDetails)`. you can obtain urls
   by `DropDoneDetails.urls`.

## 0.0.1

a file drop plugin for flutter desktop platforms.

* add Linux support.
* add Windows support.
* add macOS support.

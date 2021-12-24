# Changelog

## 0.3.0

** BREAK CHANGES**
* replace DropDoneDetails property `urls: List<Uri>` to `files: List<XFile>`. which is more general.

## 0.2.0 (2021/11/23)

Add web support

## 0.1.2 (2021/11/10)

[Linux] Fix do not work on Wayland.

## 0.1.1 (2021/11/8)

update plugin description.

## 0.1.0 (2021/9/2)

1. add android support. (preview)
2. expose pointer coordinates.

**BREAK CHANGE**:

1. Change `onDragEntered`,`onDragExited` and `onDragUpdated` callbacks signature from `VoidCallback`
   to `void Function(DropEventDetails)`.
2. Change `DropDoneDetails` from `void Function(List<Uri>)` to `void Function(DropDoneDetails)`. you can obtain urls
   by `DropDoneDetails.urls`.

## 0.0.1  (2021/8/18)

a file drop plugin for flutter desktop platforms.

* add Linux support.
* add Windows support.
* add macOS support.

# Changelog

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

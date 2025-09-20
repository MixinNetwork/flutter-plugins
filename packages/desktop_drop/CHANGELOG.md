# Changelog

## 0.7.0

[macOS] Robust multi-source drag & drop.

* Prefer `public.file-url` / legacy filename arrays when present; fall back to
  `NSFilePromiseReceiver` (file promises) otherwise.
* Handle directories (`isDirectory`) and surface as `DropItemDirectory`.
* Add `fromPromise` to `DropItem` so apps can distinguish promise-based drops.
* Generate security-scoped bookmarks only for paths outside the app container
  (skip/empty for promise files in `.../tmp/Drops/...`).
* Per-drop unique destination for promised files to avoid name collisions.
* Thread-safe collection of drop results when receiving promises.
* Dart guards: no-op `start/stopAccessingSecurityScopedResource` on empty
  bookmarks.
* Bump macOS minimum to 10.13 (SPM/Podspec).

## 0.6.1

* Fix desktop_drop Linux snap build failure due to missing stdlib.h include (#425)

## 0.6.0

Migrate macOS to SPM, fix web build.

* https://github.com/MixinNetwork/flutter-plugins/pull/398
* https://github.com/MixinNetwork/flutter-plugins/pull/399
* https://github.com/MixinNetwork/flutter-plugins/pull/403

## 0.5.0

* upgrade web version to 1.0.0

## 0.4.4

* fix build on android [#285](https://github.com/MixinNetwork/flutter-plugins/pull/285)
  by [AdamVe](https://github.com/AdamVe)

## 0.4.3

* fix windows build warning C4701

## 0.4.2

* fix crash on Windows when app exit

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

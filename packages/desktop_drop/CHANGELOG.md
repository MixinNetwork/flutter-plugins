# Changelog

## 0.9.1

- Windows: Fix a startup crash caused by queued platform tasks being freed before execution on affected Flutter engines. ([#526](https://github.com/MixinNetwork/flutter-plugins/pull/526))

## 0.9.0

### Breaking changes

- Require Flutter 3.47.7 / Dart 3.13.5 or later and upgrade to `cross_file` 0.4.
- Replace `onDragDone(DropDoneDetails)` with required, async-capable `onDrop(DropDetails)`. Consume typed `items` instead of `files`.
- Replace `DropItemFile` and `DropItemDirectory` with `DropFileItem` and `DropDirectoryItem`. Read files through `item.file` and list directories through `item.directory.list()`. `DropItem` no longer extends `XFile`; forwarded file methods and byte-backed drop-item constructors are removed.
- Limit provider access and temporary transfer files to the lifetime of `onDrop`. Await all reads and directory listings, and save content needed later before the callback returns.
- Rename hover callbacks to `onEnter`, `onMove`, and `onLeave`, and rename `enable` to `enabled`. Hover callbacks receive `DragDetails`; `onLeave` takes no arguments and also clears hover on drop, rejection, or disabling.
- Select one accepting target through Flutter hit testing, with parent fallback when a child rejects a drop. Overlapping targets no longer independently receive the same drop.
- Rename `extraAppleBookmark` to `appleBookmark` and `fromPromise` to `isPromised`. Use nullable `localPath` only for filesystem-backed content.
- Replace `rawText` with MIME-typed `DropStringItem` values. Linux portal keys are resolved by the plugin. Raw listener registration and the old broadcast event classes are removed. See the [migration guide](https://github.com/MixinNetwork/flutter-plugins/tree/desktop_drop-v0.9.0/packages/desktop_drop#migrating-from-08x-to-090).

### Features

- Receive files, directories, plain text, HTML, and URI lists as typed items. Read provider-backed files and directory contents through `XFile` and `XDirectory`; URLs remain strings without automatic downloads.
- Add per-target `acceptedKinds` filtering and optional synchronous `onWillAccept` conditions. Configure copy, move, or link feedback with `operation`, subject to source and platform support.
- Preserve source MIME types and infer missing file MIME types from names without reading file contents.
- iOS: Add drag-and-drop support on iOS 13 and later, with copy-only acceptance and automatic cleanup of temporary transfers after `onDrop`.
- Windows: Support virtual files, directories, and native image content, retaining source resources through asynchronous processing.
- Android: Add synchronous drop acceptance, provider-backed file and directory reads, and explicit directory authorization through `DesktopDrop.instance.requestDirectoryAccess` when the source does not grant child access. Reads do not open permission UI.

### Fixes

- Web: Handle mixed file/string drags and files without filesystem entries, and clear hover state after file-less drops. ([#503](https://github.com/MixinNetwork/flutter-plugins/pull/503); thanks [jamesaorson](https://github.com/jamesaorson))
- Linux: Keep portal transfers alive until file resolution completes so drops from sandboxed sources can succeed. ([#505](https://github.com/MixinNetwork/flutter-plugins/pull/505); thanks [sun-jiao](https://github.com/sun-jiao))
- macOS: Preserve mouse interaction with embedded native views outside an active drag. ([#436](https://github.com/MixinNetwork/flutter-plugins/pull/436); thanks [gicha](https://github.com/gicha))

## 0.8.4

* fix: use builtInKotlin property to conditionally apply KGP [#500](https://github.com/MixinNetwork/flutter-plugins/pull/500)
  by [loucass](https://github.com/loucass)

## 0.8.3

* [Android] Fix Kotlin configuration for AGP 8 and AGP 9 hosts [#498](https://github.com/MixinNetwork/flutter-plugins/pull/498)
  by [loucass](https://github.com/loucass)

## 0.8.2

* [Android] Restore compatibility with Android Gradle Plugin versions below 9 by applying the Kotlin Gradle Plugin conditionally, while continuing to use built-in Kotlin on AGP 9 and later [#495](https://github.com/MixinNetwork/flutter-plugins/pull/495)
  by [loucass](https://github.com/loucass)
* [Android] Hosts on AGP versions below 9 must provide Kotlin Gradle Plugin 2.0.0 or later because `desktop_drop` uses the `kotlin.compilerOptions` DSL. Apps using an older KGP version must upgrade it before updating `desktop_drop`

## 0.8.1

* [desktop_drop] [Linux] register the `application/vnd.portal.filetransfer` drag target and deliver its key via a new `performOperation_portal` channel message
* [desktop_drop] [Linux] resolve portal transfer keys through `org.freedesktop.portal.FileTransfer`, so drops from sandboxed sources yield openable document-portal paths
* [desktop_drop] expose the raw drag payload in `DropDoneEvent.rawText` / `DropDoneDetails.rawText`

## 0.8.0

**BREAKING CHANGE**

* [Android] Migrate to built-in Kotlin. Android host apps must use Android Gradle Plugin 9 or later.

## 0.7.1

* update worksapce
* [desktop_drop_web] fix: loop readEntries() to retrieve all directory children on web [#473](https://github.com/MixinNetwork/flutter-plugins/pull/473)
  by [TerryHuangHD](https://github.com/TerryHuangHD)
* [desktop_drop]: `on_focus_in_event` should return `gboolean` [#472](https://github.com/MixinNetwork/flutter-plugins/pull/472)
  by [imnotlxy](https://github.com/imnotlxy)
* [worksapce]: fix foramt
* Handle SMB URIs in Linux desktop_drop path parsing [#474](https://github.com/MixinNetwork/flutter-plugins/pull/474)
  by [app/copilot-swe-agent](https://github.com/app/copilot-swe-agent)

## 0.7.0

[Android] Upgrade Android compileSdk and Kotlin version. (#444) 
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

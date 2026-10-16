# desktop_drop

[![Pub](https://img.shields.io/pub/v/desktop_drop.svg)](https://pub.dev/packages/desktop_drop)

Receive files, directories, text, and URLs dragged into Flutter applications.
Each `DropTarget` decides which content to accept.

Requires Flutter 3.47.7 / Dart 3.13.5 or later.

| Platform | Supported |
|----------|-----------|
| Windows  | ✅        |
| Linux    | ✅        |
| macOS    | ✅        |
| iOS 13+  | ✅        |
| Web      | ✅        |
| Android  | ✅        |

## Usage

```dart
import 'package:desktop_drop/desktop_drop.dart';

DropTarget(
  acceptedKinds: const {DropItemKind.file},
  onDrop: (details) async {
    for (final item in details.items.whereType<DropFileItem>()) {
      final bytes = await item.file.readAsBytes();
      print('${item.name}: ${bytes.length} bytes');
    }
  },
  child: const SizedBox(width: 200, height: 200),
)
```

By default, targets accept all content kinds using copy. `acceptedKinds` accepts
any drag containing a matching kind; it does not filter the delivered items.
See the [example app](example) for files, directories, text, and nested targets.

## Receiving content

| Item | Access |
|------|--------|
| `DropFileItem` | `name`, `mimeType`, and `file` (`XFile`) for reads |
| `DropStringItem` | `mimeType` and `value`, including `text/plain`, `text/html`, and `text/uri-list` |
| `DropDirectoryItem` | `name` and `directory.list()` for immediate `XFile` / `XDirectory` children |

- **Await all reads inside `onDrop`.** Provider access and temporary files are
  released when the callback completes or throws. Save content there if you need
  it later. No manual disposal is required.
- Files and directories may have no `localPath`. Read through `file` or
  `directory` instead. Use `file.openRead()` to stream large files.
- A drag can contain several representations of the same content, such as an
  image file, HTML, and a URL. Choose which to use. URLs are delivered as strings;
  the plugin does not download them.
- Android directory reads never open permission UI. If the source does not grant
  access to children, `directory.list()` throws `PlatformException` with code
  `directory_access_required`. Explain the request in your UI, then explicitly
  call `DesktopDrop.instance.requestDirectoryAccess(directory: item)` after a
  user action and retry listing. Await the entire flow inside `onDrop`; access
  expires when it finishes. Cancelling authorization throws
  `directory_access_denied`. No broad storage access is used.
- Sandboxed macOS files and directories may supply an `appleBookmark`. Keep
  security-scoped access active while reading, and stop access afterward.

## Accepting drops

Use the optional `onWillAccept` callback for additional conditions:

```dart
DropTarget(
  acceptedKinds: const {DropItemKind.file},
  onWillAccept: (details) => details.items.any(
    (item) => item.kind == DropItemKind.file && item.mimeType == 'image/png',
  ),
  onDrop: (details) async {
    for (final item in details.items.whereType<DropFileItem>()) {
      if (item.mimeType != 'image/png') continue;
      final bytes = await item.file.readAsBytes();
      print('${item.name}: ${bytes.length} bytes');
    }
  },
  child: const SizedBox(width: 200, height: 200),
)
```

`onWillAccept` receives `DragDetails` with preview `items` and local/global
positions. It returns bool synchronously. Do not call `setState`, perform I/O,
or make platform calls here. Preview fields may be absent until drop; a MIME
type does not validate file contents. Directory targets tentatively accept
incomplete file previews until the source reveals whether they are directories.

Set `operation` to `DropOperation.move` or `link` if needed. Unsupported operations
reject the drop. Move can tell the source to remove its data; errors during async
`onDrop` processing may not undo that operation. `DropDetails.operation` reports
the accepted operation alongside the received `items` and positions.

Nested targets follow Flutter's hit-test path. A rejecting child can fall back to
an accepting parent. Use `onEnter`, `onMove`, and `onLeave` to update hover UI.
`onLeave` takes no arguments and also clears hover on drop, rejection, or disabling.
These callbacks can call `setState`. Set `enabled: false` to disable a target.

## macOS secondary windows

For `desktop_multi_window`, register the plugin for each new engine in
`MainFlutterWindow.swift`, after the main window's generated plugin registration:

```swift
import desktop_drop
import desktop_multi_window

FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
  DesktopDropPlugin.register(
    with: controller.registrar(forPlugin: "DesktopDropPlugin"))
}
```

## Migrating from 0.8.x to 0.9.0

Version 0.9.0 changes the public API and requires Flutter 3.47.7 / Dart 3.13.5
or later. Update existing targets and content handling using the mapping below.

| 0.8.x | 0.9.0 |
|-------|-------|
| `onDragDone(DropDoneDetails)` | Required `onDrop(DropDetails)`, which can be async |
| `details.files` | `details.items`, containing files, directories, and strings |
| `onDragEntered` / `onDragUpdated` | `onEnter` / `onMove`, receiving `DragDetails` previews |
| `onDragExited(details)` | `onLeave()`, with no arguments |
| `enable` | `enabled` |
| `DropItemFile` | `DropFileItem`; read through `item.file` (`XFile`) |
| `DropItemDirectory.children` | `DropDirectoryItem.directory.list()`, a stream of immediate `XFile` / `XDirectory` children |
| `item.path` | Optional `item.localPath`; use the file or directory API when null |
| `item.extraAppleBookmark` / `item.fromPromise` | `item.appleBookmark` / `item.isPromised` |
| `DropDoneDetails.rawText` | `DropStringItem.value`, with its `mimeType` |

For an existing file-only receiver, replace `onDragDone` with an async `onDrop`:

```dart
DropTarget(
  acceptedKinds: const {DropItemKind.file},
  onDrop: (details) async {
    for (final item in details.items.whereType<DropFileItem>()) {
      final bytes = await item.file.readAsBytes();
      // Save or process the bytes before this callback returns.
      print('${item.name}: ${bytes.length} bytes');
    }
  },
  child: const SizedBox(width: 200, height: 200),
)
```

`DropItem` no longer extends `XFile`. Move file reads such as `readAsBytes()` and
`openRead()` to `item.file`. The old byte-backed drop-item constructors and
forwarded `saveTo()` method are removed. To retain content, read or copy it to
application-owned storage inside `onDrop`. Await directory listings and all
provider reads before returning: callback completion releases provider access
and deletes temporary transfer files, including macOS promised files. Original
local files are not deleted.

Targets now accept all content kinds by default. Use `acceptedKinds` to keep a
file-only receiver, and filter `details.items` as shown above because accepting
a kind does not remove other representations from the delivered items. Use
optional `onWillAccept` for additional synchronous conditions. Copy is the
default operation; set `operation` explicitly to request move or link.

Target selection now follows Flutter hit testing. Overlapping targets no longer
each receive the same drop: the first enabled target that accepts it receives
it, with parent fallback when a child rejects it. `onLeave` also clears hover
on drop, rejection, or disabling. Use `behavior` to control hit testing.

Plain text, HTML, and URI lists are delivered as `DropStringItem` with their MIME
types. URLs are strings and are not downloaded into files. On Linux, portal
transfers are resolved by the plugin; consume the resulting file items instead
of resolving a portal key from `rawText`.

Raw listener registration and the old broadcast event classes (`DropEvent`,
`DropEnterEvent`, `DropUpdateEvent`, `DropExitEvent`, and `DropDoneEvent`) are
removed. Use `DropTarget` callbacks instead. The macOS security-scoped access
methods on `DesktopDrop.instance` remain available with the renamed
`appleBookmark` field.

## License

See [LICENSE](LICENSE). Vendored Dart API DL sources retain their
[upstream BSD license](src/vendor/LICENSE).

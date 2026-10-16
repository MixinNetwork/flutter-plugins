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

## Migrating from the previous API

- Replace `onDropDecision` with optional boolean `onWillAccept` and a fixed
  `operation` (defaults to copy). `DropOperation.reject` is removed.
- Use `acceptedKinds` for basic type filtering and `details.items` for previews.
  `DropOffer`, `offer`, and `isComplete` are no longer part of the public API.
- Use `DragDetails` for hover/acceptance and `DropDetails` for `onDrop`.
  Older `onDragDone` users should switch to `onDrop` and typed `items`.
- Rename hover callbacks to `onEnter`, `onMove`, and `onLeave`; `onLeave` has no
  arguments. Rename `enable` to `enabled`. `onDrop` is now required.
- Read files through `DropFileItem.file` and directories through
  `DropDirectoryItem.directory`. Await reads before `onDrop` returns.

## License

See [LICENSE](LICENSE). Vendored Dart API DL sources retain their
[upstream BSD license](src/vendor/LICENSE).

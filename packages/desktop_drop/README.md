# desktop_drop

[![Pub](https://img.shields.io/pub/v/desktop_drop.svg)](https://pub.dev/packages/desktop_drop)

Receive files, text, and URLs dragged into Flutter applications. Each `DropTarget`
chooses synchronously whether to reject, copy, move, or link the current content.

Requires Flutter 3.47.7 / Dart 3.13.5 or later. This API redesign is intended for
the next major release; the package version is updated separately when releasing.

| Platform | Operations and feedback |
|----------|-------------------------|
| macOS | copy/move/link within the source mask; synchronous native decision |
| iOS 13+ | copy only; synchronous UIKit proposal and automatic transfer cleanup |
| Windows | copy/move/link within the source mask; synchronous native decision |
| Linux | copy/move/link within the source actions; asynchronous GTK status/finish |
| Web | copy/move/link within `effectAllowed`; synchronous DOM decision |
| Android (preview) | copy only; Dart filters delivery after the listener's initial acknowledgement |

## Usage

Choose an operation from the advertised metadata, then consume typed items:

```dart
DropTarget(
  onDropDecision: (event) => event.offer.items.any(
    (item) => item.kind == DropItemKind.file,
  ) ? DropOperation.copy : DropOperation.reject,
  onDrop: (event) async {
    for (final item in event.items) {
      switch (item) {
        case DropFileItem(:final file):
          // file is an XFile. Read only when your application needs the content.
          final bytes = await file.readAsBytes();
          print('${item.name}: ${bytes.length} bytes');
        case DropStringItem(:final mimeType, :final value):
          print('$mimeType: $value');
        case DropDirectoryItem():
          final children = await item.directory.list().toList();
          print('${item.name}: ${children.length} entries');
      }
    }
  },
  child: const SizedBox(width: 200, height: 200),
)
```

## Typed content

`DropEvent.items` is an immutable list of `DropItem`, a sealed class:

| Item | Contents |
|------|----------|
| `DropFileItem` | `name`, optional `mimeType` and `localPath`, and an `XFile` in `file` |
| `DropStringItem` | `mimeType` and the original string `value` |
| `DropDirectoryItem` | `name`, optional `localPath`, and an `XDirectory` in `directory` |

A file can reference a real local path, a browser Blob, or a native data provider.
`localPath` is null for content that has no filesystem path. Use `item.file` to
read it instead of opening `localPath`. XFile 0.4 provides `readAsBytes()`,
`readAsString()`, `openRead(start, end)`, `length()`, and `lastModified()`;
metadata methods can return null. `openRead` follows XFile's range contract,
including rejecting equal start/end offsets. `item.directory.list()` returns a
`Stream<XEntity>` containing immediate `XFile` and `XDirectory` children on demand;
it does not recursively read file contents. Local directories reuse
`XDirectory.fileSystem()`. Browser entries and Windows virtual directories use
an internal XDirectory adapter without inventing a local filesystem path.

Applications consume files and directories through XFile read methods and
XDirectory.list(). Where the system permits it, native content is requested only
by these calls. iOS requires provider requests to start inside `performDrop`, so
accepted iOS drops start file transfers immediately and retain temporary copies
until `onDrop` completes. macOS file promises remain lazy. Available string
representations and metadata are included in the event.

Provider references are valid only during `onDrop`. Await all reads and directory
listings in its async callback. The plugin releases readers, source permissions,
and temporary transfer resources when the callback returns or throws. This also
applies if delivery is discarded because the target was disabled or disposed.
There is no manual event disposal. Save content explicitly inside the callback
if it is needed later; strings and bytes already read remain usable. Original
local files are never deleted. Provider or permission failures can still occur
during the callback and are reported by the requesting Future or Stream.

Strings retain their MIME types. Plain text is `text/plain`, HTML is `text/html`,
and URI lists are `text/uri-list`. URI lists retain line separators and comments;
applications parse them according to that format. Browser custom string formats
are also passed through. Native adapters normalize supported OS formats into
these representations; arbitrary private native formats are not automatically
interpreted as strings.

One drag can provide several representations of the same content. For example,
a browser image may provide an image file, an HTML fragment, and a URI list.
They are all exposed; applications choose which representation to consume.
An image is a file item with an image MIME type, not a special image item.
Files retain the MIME type supplied by the source. When it is missing or empty,
the plugin infers it from the filename extension for both hover previews and
dropped items, without reading the contents. Unrecognized extensions remain
null. This metadata does not validate the file or guarantee that an application
can decode its format.

The plugin never downloads URLs, fetches HTML resources, or converts a URL into
a file. An image URL, including a data URL, remains a string unless the source
also supplies file/image content. Saving, decoding, uploading, and downloading
are application decisions.

## Decisions and target selection

`onDropDecision` returns `DropOperation.reject`, `copy`, `move`, or `link` and must
return quickly. Inspect `event.offer.items` and in-memory application state.
Each `DropItemPreview` has a `kind`, optional MIME/name/local path, and a `value`
when a string value is already available. Do not call `setState`, perform I/O,
wait for a Future, or call a platform channel inside the decision callback.
Exceptions reject that candidate and are reported through `FlutterError`.

`event.allowedOperations` lists operations supported by both the source and
adapter. Reject is always available and is not listed. Unsupported choices reject
the candidate and allow parent fallback; they are never silently changed to copy.
Hover callbacks and `onDrop` expose the selected `event.operation`. During the
decision callback this field is reject because no operation has been selected yet.

Preview data can be incomplete. Browsers protect string values and filenames
during hover, and iOS protects provider values until drop; macOS promises, Windows virtual files, and Linux portals may not
have paths yet. A rule that rejects every incomplete offer can prevent dropping
altogether. Tentatively accept advertised metadata, then validate available values
in the final decision on release where available. iOS proposals use metadata;
validate actual string values in `onDrop`. A promised file can still have an
incomplete offer at the final decision. Readable resources are supplied to `onDrop`.

Selection uses Flutter's actual hit-test path. The first enabled target returning
an allowed operation receives the event. A rejecting child can fall back to an
accepting ancestor. Opaque widgets occlude siblings; `behavior` has the same
meaning as Flutter's `HitTestBehavior`. Positions include Flutter transforms.
An accepted drop stays assigned to that target during delivery;
delivery is discarded if the target is disposed or disabled.

`onDragEntered`, `onDragUpdated`, and `onDragExited` describe the selected target.
Rejection, a final drop, and disabling the target clear hover. These callbacks
and `onDrop` can update application state normally.

The operation is a protocol result, not a filesystem move or shortcut command.
Selecting move can tell the source to remove its data. Only choose it when your
application can honor that meaning. Acknowledgement does not wait for application
work in `onDrop`; native event delivery can happen after acknowledgement. Later
errors cannot universally roll back the source operation. Source/provider content
can fail after acceptance; explicit reads report failures through their Future or Stream.
On macOS, a final operation that differs from the last hover proposal rejects the
drop because AppKit's final callback can return only success or failure.

## Platform details

macOS, iOS, and Windows share a C ABI bridge. With merged platform/UI threads, native
code invokes an isolate-local Dart callback after checking isolate ownership.
With separate threads, it sends a copied request and waits at most 100ms. Timeout
rejects that operation. Late replies, old registrations, and disposed destinations
cannot change a later decision. Thread mode is detected at runtime.

Windows exposes existing file paths and virtual files advertised through
FileGroupDescriptor/FileContents. Sources supporting asynchronous extraction are
opened on demand during the async `onDrop` callback. For synchronous sources,
an accepted native drop acquires and owns the storage medium before returning
to Windows. Applications then read that medium through the same `XFile` API;
the plugin does not automatically write it to disk. Stream readers use independent
cursors when supported, otherwise retaining requested bytes for repeat reads.
Media and the source session are released when `onDrop` completes. Acquisition
and read failures are returned to Dart. PNG and DIB keep their source formats; bitmap
handles are converted to BMP only when read. Structured storage is serialized
only for an active read. Relative virtual directories use a metadata tree.

iOS uses `UIDropInteraction` and `NSItemProvider`. It advertises copy only, so
sources can keep their contents until the application's asynchronous work ends.
Provider types supply MIME metadata during hover; protected string values remain
unavailable until drop. UIKit requires all provider requests to start inside
`performDrop`. The adapter starts accepted transfers there, copies returned files
before the provider's temporary URL expires, then delivers the originally selected
target. File and directory access still uses XFile/XDirectory. Failed file transfers
surface as read errors; unavailable string representations leave the offer incomplete.
Temporary files are deleted after `onDrop` or discarded delivery, including when
a target is disabled or removed while the transfer is running. Move and link are
not advertised. See [Apple's drop callback contract](https://developer.apple.com/documentation/uikit/uidropinteractiondelegate/dropinteraction(_:performdrop:)).

macOS exposes file URLs, file promises, and native PNG/TIFF providers. Accessing
a promise's contents or filesystem metadata during async `onDrop` starts its
receiver once. AppKit writes the receiver's promised files into a temporary
directory shared by that drop. Concurrent requests share the reception result;
subsequent reads, metadata queries, and directory listings reuse the existing
`XFile.fileSystem` and `XDirectory.fileSystem` implementations. File contents and
directory entries do not pass through the plugin's native reader. Temporary
files are removed when `onDrop` completes; cleanup waits for any pending
reception. Reception failures propagate to the requesting Future or Stream.
Existing filesystem references and native image
providers are read on demand. Files/directories can carry an `appleBookmark` for
security-scoped access. Keep access active while reading a sandboxed directory
and its children, then balance it with a stop.

Linux uses asynchronous GTK selection/status/finish APIs and leaves its main loop
running. Dart queries have the same 100ms deadline. Portal `RetrieveFiles` resolves
path/access metadata only for an actual drop. Image/named content selections are
requested only by a read. GTK delivers a whole selection at once; the active
reader holds those bytes until closed. Drop completion closes remaining readers,
releases cached selection bytes, and removes the session before finishing the
GTK drag. URI-list strings remain available beside local file references;
remote URIs are not interpreted as local filesystem paths.

Web preserves source File/Blob objects and string item MIME types. It captures
references while the DOM drop event is readable and accesses file bytes only on
request. Object URLs and directory references are released after `onDrop`,
including resources discovered while listing children. Directory reads consume
every batch, including folders with more than 100 entries. `getAsFile()` fallback
is supported. Capture listeners prevent
default navigation and preserve unrelated DOM handlers. Blob reads do not fetch
their preview URL. Callback completion revokes URLs created for the Blob references;
normal browser/provider failures are propagated by reads.

Android remains a preview implementation for the primary Flutter view. Its
synchronous listener initially acknowledges the drop; later Dart rejection
filters delivery. Accepted URI files remain provider references, with drag
permissions held until callback completion or Activity teardown. Reads open
the provider stream directly; virtual documents use a provider-advertised byte
MIME type. No URI file is copied into application cache. URI/provider or Activity
lifecycle failures propagate to Dart. Hover metadata cannot distinguish text
from a text file URI, so tentative file previews are validated at drop.
Native additional views on macOS/Linux need their own registrar; unattached views
fail initialization explicitly.

### macOS secondary windows

Each `desktop_multi_window` window has its own engine. Register `desktop_drop`
with the new controller in `MainFlutterWindow.swift` after the main window's
generated plugin registration:

```swift
import desktop_drop
import desktop_multi_window

FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
  DesktopDropPlugin.register(
    with: controller.registrar(forPlugin: "DesktopDropPlugin"))
}
```

The destination is attached to that registrar's view, including for secondary
windows. Register any other plugins needed by the new engine in the same callback.

### Build modes and host configuration

Web registration uses the same direct DOM adapter in debug, profile, and release.
Optimized builds can bundle Dart source files, so the absence of an individual
`desktop_drop_web.dart` entry in browser developer tools does not indicate that
the plugin is missing. Use source maps when inspecting optimized builds.

Android hosts must satisfy the SDK minimums above. The plugin configures Kotlin
for both AGP 8 and AGP 9; on AGP 9, `android.builtInKotlin` must match the host's
Kotlin mode. A `GeneratedPluginRegistrant` error saying `DesktopDropPlugin` is
missing is a native build/registration error, not a Dart drag callback error.
Include the first Kotlin/Gradle failure and host Gradle configuration when
reporting it; changing Dart acceptance rules cannot repair that build failure.

## Migrating from the previous API

- Replace `onDragDone(DropDoneDetails)` with `onDrop(DropEvent)` and iterate
  `event.items`. There is no compatibility alias for the previous payload.
- Make `onDrop` async and await provider reads and directory listings before
  returning. Sources are released automatically when it completes; save the
  content inside the callback instead of retaining provider references.
- Switch on `DropFileItem`, `DropStringItem`, and `DropDirectoryItem`.
  File reads move to `item.file`, an XFile 0.4. Use `localPath` only when non-null;
  old file `path`, forwarded read methods, and `saveTo()` are removed.
  Directory reads use `item.directory.list()`, which returns XFile and XDirectory
  children rather than drop items.
- Read text, HTML, and URI lists from `DropStringItem.value` using its MIME type.
  The separate `files`, `text`, `urls`, and Linux portal-key fields are removed.
  Portal transfers have already been resolved by native code.
- Replace boolean `onWillAccept` with `onDropDecision`, returning an operation.
  Inspect `offer.items` (`DropItemPreview`) rather than `offer.types` or separate
  file/text/URL fields. Check `allowedOperations` before selecting move or link.
- Hover callbacks still use `DropEventDetails`. File/directory macOS bookmarks
  are exposed as `appleBookmark`; promise metadata uses `isPromised`.
- `behavior` replaces the former hit-test setting. Raw listeners and the old
  broadcast event classes are removed; selection belongs to the widget hit test.

## Development

All native communication uses the shared FFI bridge. Synchronous decisions on
Windows/macOS/iOS use a thread-checked callback or a bounded Dart-port round trip.
Asynchronous events and resource reads use request IDs and Dart ports; native
adapters dispatch system operations to their platform thread. A drop reply is
sent after the application's `onDrop` Future completes, then the adapter releases
its resources. iOS/macOS share their Swift transport and resource lifetime
implementation in `darwin/`, configured with `sharedDarwinSource`. Android connects the same
bridge to Kotlin through JNI. Web continues to pass Dart objects directly.

Messages use Flutter's standard binary codecs over FFI; no MethodChannel is
registered. Connections are matched to `PlatformDispatcher.engineId`, while
view IDs and generations keep drop decisions and source references scoped.

Shared C/C++ sources live in `src/`. Windows, Linux, and Android compile them
directly. The Darwin target forwards to these sources for Swift Package Manager
and CocoaPods. Its standalone public C header is generated from the shared ABI
by the same ffigen script; all platforms use the same implementation.

FFI declarations are generated from
`src/desktop_drop_ffi.h`:

```sh
dart run tool/ffigen.dart
dart run tool/test_native_bridge.dart
flutter test --no-pub test/drop_target_test.dart
flutter test --no-pub --platform chrome test/browser
```

The generator uses `ffigen`'s Dart configuration API. Commit the generated bindings
and the Darwin public header with ABI changes. The native bridge tests cover merged callbacks, thread
ownership, separate-thread replies, timeout recovery, late replies, registration
generations, and disposal.

## LICENSE

See LICENSE. The vendored Dart API DL sources retain their upstream BSD license
in `src/vendor/LICENSE`.

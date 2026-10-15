# desktop_drop

[![Pub](https://img.shields.io/pub/v/desktop_drop.svg)](https://pub.dev/packages/desktop_drop)

Receive files, text, and URLs dragged into Flutter applications. Each `DropTarget`
chooses synchronously whether to accept the current content at its location.

Requires Flutter 3.47.7 / Dart 3.13.5 or later. This API redesign is intended for
the next major release; the package version is updated separately when releasing.

| Platform | Acceptance feedback |
|----------|---------------------|
| macOS | Synchronous native decision |
| Windows | Synchronous native decision |
| Linux | GTK status/finish after an asynchronous Dart reply |
| Web | Synchronous DOM decision |
| Android (preview) | Dart filters delivery; the Android listener initially acknowledges the drop |

## Usage

Explicitly choose the representations your application accepts:

```dart
DropTarget(
  onWillAccept: (details) => details.offer.types.contains(DropType.file),
  onDragDone: (details) {
    for (final file in details.files) {
      // DropItem retains XFile APIs, directory children on Web,
      // and macOS security-scoped bookmark information.
      print(file.name);
    }
  },
  child: const SizedBox(width: 200, height: 200),
)
```

Two destinations can use different rules. Predicates read current application
state on every query, including a final query when the user releases the drag:

```dart
Row(
  children: [
    DropTarget(
      onWillAccept: (d) => editingEnabled && d.offer.types.contains(DropType.text),
      onDragDone: (d) => insertText(d.text!),
      child: const Text('Text'),
    ),
    DropTarget(
      onWillAccept: (d) => d.offer.types.contains(DropType.url) &&
          (!d.offer.isComplete || d.offer.urls.every((url) => url.scheme == 'https')),
      onDragDone: (d) => openLinks(d.urls),
      child: const Text('HTTPS links'),
    ),
  ],
)
```

`onWillAccept` must return quickly. Read the supplied offer and in-memory state.
Do not call `setState`, perform I/O, wait for a Future, or call a platform channel
inside this callback. An exception rejects that candidate and is reported through
`FlutterError`. Hover callbacks and `onDragDone` run after the decision; they can
update application state normally. Supported native operations are copy only.

## Content and target selection

`DropOffer.types` describes file/text/URL representations. A drag can advertise
several representations at once. `files` contains metadata (`name`, optional
`path`, `mimeType`, `isDirectory`, and `isPromised`), not readable file contents.
`text` and `urls` contain values when the source makes them available.

Check `isComplete` before requiring a value. Browsers protect text and URL values
while hovering. macOS promised files do not have paths before materialization.
Linux portal files become accessible after the final drop resolves the transfer.
A predicate that rejects all incomplete offers may prevent a source from dropping
at all. To support those sources, tentatively accept advertised types and validate
the available metadata in the final query. A macOS file promise can still have an
incomplete offer at that final query. Inspect its advertised names/types; the
readable paths arrive in `onDragDone`.

Selection uses Flutter's hit-test path in the relevant view. The first enabled
accepting target receives the event. A rejecting nested child allows an accepting
parent to receive it. Opaque widgets block targets behind them. `behavior` has the
same meaning as Flutter's `HitTestBehavior`. Global and local positions include
Flutter transforms. A final accepted drop stays assigned to that target while
files are read; it is discarded if the target is disposed or disabled.

`onDragEntered`, `onDragUpdated`, and `onDragExited` describe the selected target.
Rejection, a final drop, and disabling the target clear its hover state. The
example has file, TXT, PNG, text, URL, and nested destinations, with manual switches
for changing acceptance during a drag.

## Platform details

macOS and Windows use one C ABI bridge. With merged platform/UI threads, native
code invokes an isolate-local Dart callback directly after checking isolate
ownership. With separate threads it sends a copied request to Dart and waits at
most 100ms. Timeout rejects that operation. Late responses, old registrations,
and disposed destinations cannot change a later decision. Flutter's thread mode
is detected at runtime; applications do not configure it through this package.

Linux uses GTK's asynchronous selection/status/finish APIs and leaves its main
loop running. Dart acceptance queries have the same 100ms deadline. Portal
`RetrieveFiles` is called only for an actual drop. `DropDoneDetails.rawText` retains
the original URI list or portal transfer key; do not resolve that key again.

Web decisions happen before the DOM drag callback returns. Accepted file and
folder reads run afterward. Directory reads consume all batches, including
folders containing more than 100 entries. Files exposed only by `getAsFile()`
are supported. Existing DOM event handlers are preserved.

Android remains a preview implementation for the primary Flutter view. Its
synchronous `OnDragListener` cannot return the later Dart result to the source;
rejected data is not delivered to `onDragDone`. Accepted URI files are copied to
application cache while drag permissions are held. The application owns cleanup
of delivered cache files; failed copies and native lifecycle cancellations are
cleaned up by the plugin. Hover MIME types cannot distinguish plain text from a
text file URI, so Android tentatively advertises file support until the final
query inspects the actual items. Native additional views on macOS/Linux require
their own plugin registrar; an unattached view fails initialization explicitly.

## Migrating from the previous API

- Add `onWillAccept` to every `DropTarget`. To retain file-only reception, use
  `d.offer.types.contains(DropType.file)`.
- Use `DropEventDetails` for hover callbacks. Read metadata from `details.offer`.
- Continue using `DropDoneDetails.files` for file contents, directories, and macOS
  bookmarks. `text` and `urls` provide the newly supported content.
- `behavior` replaces the former hit-test setting. Raw event listeners and the old
  broadcast event classes are removed. Selection is owned by the widget hit test.

## Development

FFI declarations are generated from
`macos/desktop_drop/Sources/desktop_drop_ffi/include/desktop_drop_ffi.h`:

```sh
dart run tool/ffigen.dart
dart run tool/test_native_bridge.dart
flutter test --no-pub test/drop_target_test.dart
flutter test --no-pub --platform chrome test/browser
```

The generator uses `ffigen`'s Dart configuration API. Commit the generated bindings
with header changes. The native bridge tests cover merged callbacks, thread
ownership, separate-thread replies, timeout recovery, late replies, registration
generations, and disposal.

## LICENSE

See LICENSE. The vendored Dart API DL sources retain their upstream BSD license
in `macos/desktop_drop/Sources/desktop_drop_ffi/vendor/LICENSE`.

# Desktop Drop playground

A single desktop page for checking drop decisions, overlapping targets and
source content. Requires the Flutter/Dart versions in `pubspec.yaml`.

```sh
flutter run -d macos   # or windows, linux, chrome, or an Android device
```

The drop area and received content stay side by side. Drag the divider to resize
the panes. Lists and content scroll independently; the page never moves the
results below the targets. The macOS window opens at 1180 × 740 with a minimum
content size of 900 × 620. Hosts narrower than 800 pixels can pan horizontally.

## Targets

Parent contains two partially overlapping sibling targets, Child A and Child B.
Each target has its own acceptance preset and enabled switch. Parent accepts any
content by default; Child A accepts `text/plain` files, and Child B accepts
`image/png` files. Both presets use only the MIME type exposed by the plugin,
including during hover. Unknown types are rejected by these child targets.
Child B starts in front. **Swap layers** exchanges their stacking order without
changing their settings. The shared Action selector chooses reject/copy/move/link.
An operation unsupported by the source is rejected rather than substituted.

| Scenario | Expected behavior |
|----------|-------------------|
| A `text/plain` file onto the exposed part of Child A | Child A receives it. |
| PNG onto Child B | Child B receives it. |
| A `text/plain` file onto the overlap with Child B in front | Child B rejects; Parent receives it. The obscured Child A is not hit. |
| Swap layers, then a `text/plain` file onto the overlap | Child A receives it. |
| Swap layers, then PNG onto the overlap | Child A rejects; Parent receives it. |
| Drop onto Parent's background | Parent decides using its own preset. |
| Disable the front child | Its card still obscures the sibling; Parent can receive the drop. |
| Disable Parent and both children | Rejected. |
| Mixed text/PNG selection onto a plain-text-only target | Rejected by that target. |
| Source does not support the selected Action | Rejected. Android and iOS advertise copy only. |

Hover highlights the selected target and shows its operation. Received content
remains unchanged until another drop. On macOS, changing the action only at the
final decision rather than during hover rejects the drop.

## Content

The async `onDrop` callback reads each file and recursively lists and reads
directories. The plugin releases the sources when the callback completes.
Only the latest drop's content and read errors are retained. Original
representations are listed separately: a browser
image can include a file, HTML and a URI list. Selecting an item shows the
already received content in the adjacent viewer. The plugin does not merge
representations or invent a file from an image URL.

- Image and text previews use the received bytes. Images use a checkerboard
  background, with Fit and 100% views. Text previews show at most 64 KiB and mark
  truncation. Unsupported image decoders report that content was read but cannot
  be previewed; the bytes remain available in the hex view.
- The hex view displays the first 256 received bytes with offsets and ASCII.
- Directories show the children discovered during `onDrop`. Clicking a child
  opens its received content; Back returns to the containing directory.
- String items display their original values immediately. HTML is source text.
  URI lists show one line per entry, preserve comments, and support copying.
  No external images, previews or URLs are downloaded.
- **Details** shows MIME type, local path or source reference, promise status,
  allowed operations and original positions. It does not read file content.
- Clear and replacement discard the example's stored content. Selecting an item
  does not request the native source again. Read errors are shown in the viewer;
  retry by dropping the source again.

On macOS, reading a file promise during `onDrop` requests its reception into a
temporary directory. Once received, files and directories use the existing
`XFile` and `XDirectory` filesystem implementations. Callback completion removes
the temporary files after pending reception finishes; the example keeps its own
received bytes. A receiver is requested only once, even for concurrent reads.

## iOS

The example includes an iOS host. Run it with `flutter run -d <ios-device-id>`.
Drop files/folders from Files, photos from Photos, or text/URLs from another app
where the system supports dragging. Select **Copy**; the iOS adapter does not
offer move or link. UIKit starts file transfers at drop time. The plugin retains
its temporary copies through the async `onDrop` callback, and the example keeps
its own received bytes for later display.

## macOS bookmarks

Drop a real Finder file, open **Details**, and choose **Save bookmark**. The
bookmark button beside Received opens the saved reference even after restarting
the app. **Read with access** and **Read without access** compare sandbox behavior
using an explicit 64-byte read. Successful access is balanced with a stop. Normal
file and folder reads also keep security-scoped access active while reading.

## Manual regression

- Drag from Finder, Explorer, browsers and text editors. Check files, folders,
  selected text, URLs, HTML, native images, virtual files and file promises.
- On Windows, Chrome's text/image drag preview should remain visible over the
  window, including when the hovered target rejects it.
- On macOS, check that file promises are received during `onDrop` or report a
  read error without a crash. Also test a drop into an inactive window and source
  expiry.
- On Web, check folders with more than 100 entries and verify that image URL/HTML
  drops make no network request. MIME presets reject mismatched or unknown types
  during hover and drop, even when the browser protects filenames.
- Test the overlap in both layer orders, independent switches, parent fallback,
  unsupported actions, and viewing received content after the source is released.

Widget coverage follows the same target decision/delivery path and checks the
fixed desktop layout and overlap behavior. Real OS drag acceptance is a separate
manual check. This example does not synthesize native drags.

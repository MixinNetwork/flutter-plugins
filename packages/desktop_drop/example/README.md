# Desktop Drop playground

A small app for checking independent drop rules, nested targets, and received
content. Requires the Flutter/Dart versions specified in `pubspec.yaml`.

```sh
flutter pub get
flutter run -d macos   # or windows, linux, chrome, or an Android device
```

Wide windows show targets and the inspector side by side. Narrow windows use a
single scrollable layout. Every target has an independent manual switch. The
example does not change acceptance automatically.

## Try these scenarios

| Scenario | Expected behavior |
|----------|-------------------|
| File or folder onto **All files** | Inspector shows the receiving target and paths. |
| TXT onto **TXT files**, PNG onto **PNG files** | Matching extension is accepted; mismatches are rejected. |
| Mixed TXT/PNG selection onto **TXT files** | Rejected because every file must match. |
| Plain text onto **Text** | Inspector shows the text, with no file required. |
| Browser link onto **URLs** | Inspector shows the source's URL representation. |
| Browser image or image data URL onto **All files** | Readable image is delivered when browser/source permissions allow it; its URL is retained. |
| TXT onto **Child · TXT** | Child receives it. |
| PNG or link onto the child area | The parent receives it if its switch is on. |
| Disable child, keep parent on | Content over the child falls back to the parent. |
| Disable both parent and child | Content over the nested area is rejected. |
| Toggle another target | Other targets retain their own rules. |
| Drop, then move the pointer | Inspector retains the drop's original local/global positions. |

Drag sources can advertise multiple representations. A browser link may also be
plain text; the corresponding targets can both accept it at their own locations.
Browsers hide filenames during hover. Extension targets tentatively accept an
unknown browser preview and check actual filenames on release. Promised macOS
files must advertise a usable name to match a filename rule.

The inspector shows the latest accepted drop. **Read file** reads at most 64 bytes
and reports the file size, so large files do not fill application memory. Directory
entries are shown separately from regular files.

## macOS bookmarks

1. Drop a real file from Finder.
2. Choose **Save bookmark** in its inspector entry.
3. Restart the app.
4. Use **Read with access** to request security-scoped access and verify a read.
5. **Read without access** lets you compare sandbox behavior for the same file.

A macOS promised file is delivered into the app's temporary directory and usually
has no security-scoped bookmark. Its inspector entry identifies it as a promise.
Saved bookmarks remain in this example's preferences until replaced.

## Additional manual regression

- Drag several Apple Music tracks together; verify every advertised file or
  promise is delivered once, including multiple files with the same type.
- Drop a folder into an inactive macOS window after interacting with another
  application; verify the inspector updates without clicking the window.
- Register the plugin for a `desktop_multi_window` child engine using the package
  README instructions, then drop into the main and child windows independently.
- Serve a release/profile web build and drag files over both the Flutter surface
  and a descendant DOM element that handles its own events. Verify no navigation
  occurs and the matching target receives the drop.
- Try an image source that permits CORS, an image data URL, and a source that
  blocks CORS. For the blocked source, verify the URL remains available and the
  read error is reported without navigating away.
- Check large browser files using **Read file**; it should read only the requested
  range. Native Android debug/release builds and window-manager coexistence need
  the application's actual host configuration.

## Checks

```sh
flutter analyze --no-pub
flutter test --no-pub
```

Widget tests cover 320/800/1200-pixel windows, larger text, scrolling, independent
acceptance switches, and delivery into the inspector. Real OS drag behavior is a
separate manual check; Flutter widget gestures are not native drag sources.

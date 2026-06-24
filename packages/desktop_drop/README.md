# desktop_drop

[![Pub](https://img.shields.io/pub/v/desktop_drop.svg)](https://pub.dev/packages/desktop_drop)

A plugin which allows user dragging files to your flutter desktop applications.

|         |            |
|---------|------------|
| Windows | ✅          |
| Linux   | ✅          |
| macOS   | ✅          |
| Android | ✅(preview) |
| Web     | ✅          |

## Getting Started

1. Add `desktop_drop` to your `pubspec.yaml`.

```yaml
  desktop_drop: $latest_version
```

2. Then you can use `DropTarget` to receive file drop events.

```dart
class ExampleDragTarget extends StatefulWidget {
  const ExampleDragTarget({Key? key}) : super(key: key);

  @override
  _ExampleDragTargetState createState() => _ExampleDragTargetState();
}

class _ExampleDragTargetState extends State<ExampleDragTarget> {
  final List<XFile> _list = [];

  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) {
        setState(() {
          _list.addAll(detail.files);
        });
      },
      onDragEntered: (detail) {
        setState(() {
          _dragging = true;
        });
      },
      onDragExited: (detail) {
        setState(() {
          _dragging = false;
        });
      },
      child: Container(
        height: 200,
        width: 200,
        color: _dragging ? Colors.blue.withOpacity(0.4) : Colors.black26,
        child: _list.isEmpty
            ? const Center(child: Text("Drop here"))
            : Text(_list.join("\n")),
      ),
    );
  }
}

```

## macOS: Global Drops

On macOS there are two ways users can drop content into your app:

- In-window drag & drop over your UI (`DropTarget`).
- Drop on the app's Dock icon, or use Open With from Finder, which is an
  application-level open.

The application-level path needs small macOS app configuration in addition to
the Dart `DropTarget`.

### Files and folders via Dock or Finder

Add document types to your macOS `Info.plist` so Finder can route files and
folders to the app:

```xml
<!-- Advertise broad document types so Dock/Finder route drops to the app. -->
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>public.data</string>
      <string>public.folder</string>
    </array>
  </dict>
</array>
```

Initialize the channel early. You can observe application-level drops with a raw
listener:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  DesktopDrop.instance.addRawDropEventListener((event) async {
    if (event is DropDoneEvent && event.location == Offset.zero) {
      // Process files and directories in event.files.
    }
  });

  DesktopDrop.instance.init();
  runApp(const MyApp());
}
```

You can also opt a primary `DropTarget` into app-wide drops:

```dart
DropTarget(
  catchAppWideDrops: true,
  onDragDone: (details) {
    // Handles normal in-window drops and app-wide macOS drops.
  },
  child: child,
)
```

If multiple `DropTarget`s set `catchAppWideDrops: true`, each target can receive
the same app-wide drop. In most apps, enable it only on the primary drop area.

### Text and links via Dock Services

macOS delivers selected text and links dropped on the Dock icon through
Services. To accept those drops, configure both `Info.plist` and
`AppDelegate.swift`.

1. Add an `NSServices` entry to your macOS `Info.plist`:

```xml
<key>NSServices</key>
<array>
  <dict>
    <key>NSMenuItem</key>
    <dict>
      <key>default</key>
      <string>Drop Text into My App</string>
    </dict>
    <key>NSMessage</key>
    <string>desktopDropAcceptDroppedText</string>
    <key>NSSendTypes</key>
    <array>
      <string>NSStringPboardType</string>
      <string>public.text</string>
      <string>public.plain-text</string>
      <string>public.utf8-plain-text</string>
      <string>public.utf16-plain-text</string>
      <string>public.utf16-external-plain-text</string>
      <string>public.html</string>
      <string>public.rtf</string>
      <string>public.url</string>
    </array>
  </dict>
</array>
```

2. Install the Services provider in `AppDelegate.swift` before the app finishes
   launching:

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    if NSApp.servicesProvider == nil,
       let cls = NSClassFromString("DesktopDropServicesProvider") as? NSObject.Type {
      NSApp.servicesProvider = cls.init()
    }
    super.applicationWillFinishLaunching(notification)
  }
}
```

Dock text and link drops are delivered as memory-backed `DropItem`s. The package
exports helpers for reading those values:

```dart
import 'package:desktop_drop/desktop_drop.dart';

onDragDone: (details) async {
  for (final item in details.files) {
    if (item.isMemoryBacked && item.isTextLike) {
      final uris = await item.readAsUris();
      if (uris.isNotEmpty) {
        // Handle text/uri-list links.
        continue;
      }

      final text = await item.readAsText();
      // Handle plain text, HTML, or raw RTF content.
      continue;
    }

    // Handle real files and directories as before.
  }
}
```

The example app includes the required `Info.plist` and `AppDelegate.swift`
setup, plus a `TextDropDemo` that displays dropped text and links.

## LICENSE

see LICENSE file

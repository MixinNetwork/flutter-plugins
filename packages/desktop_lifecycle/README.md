# desktop_lifecycle
[![Pub](https://img.shields.io/pub/v/desktop_lifecycle.svg)](https://pub.dev/packages/desktop_lifecycle)

Allow your flutter desktop application to perceive whether the window is activated.

## Getting Started

1. Add `desktop_lifecycle` to your `pubspec.yaml`.

```yaml
  desktop_lifecycle: $latest_version
```

2. Then you can use `DesktopLifecycle.instance.isActive` to listen window active event.

```dart
final ValueListenable<bool> event = DesktopLifecycle.instance.isActive;

final bool active = event.value;

event.addListener(() {
  debugPrint("window activate: ${event.value}");
});

```

## LICENSE

see LICENSE file
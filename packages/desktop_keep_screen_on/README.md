# desktop_keep_screen_on

A Flutter plugin to keep the screen on in desktop platforms.

|         |   |
|---------|---|
| Windows | ✅ |
| Linux   | ✅ |
| macOS   | ✅ |

## Getting Started

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  desktop_keep_screen_on: ^0.0.1
```

## Usage

```dart
import 'package:desktop_keep_screen_on/desktop_keep_screen_on.dart';

void foo() async {
  // Keep screen on
  await DesktopKeepScreenOn.setPreventSleep(true);

  // Do something...

  // Allow screen to sleep
  await DesktopKeepScreenOn.setPreventSleep(false);
}

```

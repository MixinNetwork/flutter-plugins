# ui_device

A Flutter plugin for accessing UIDevice information on iOS.

## Usage

To use this plugin, add `ui_device` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages).

```yaml
dependencies:
  ui_device:
    git:
      url: https://github.com/MixinNetwork/flutter-plugins.git
      path: packages/ui_device
```

Then import the package:

```dart
import 'package:ui_device/ui_device.dart' as ui_device;
```

### Getting Device Information

`ui_device` provides a single method `current` which returns a `DeviceInfo` object containing various properties of the device.

```dart
final current = ui_device.current;
print(current.systemName); // e.g. "iOS"
print(current.systemVersion); // e.g. "14.4.1"
print(current.name); // e.g. "iPhone XS Max"
print(current.model); // e.g. "iPhone11,6"
```

You can also get additional information such as the `localizedModel`, `identifierForVendor`, and `isPhysicalDevice`.

```dart
final current = ui_device.current;
print(current.localizedModel); // e.g. "iPhone"
print(current.identifierForVendor); // a unique identifier for a device, persisted across app installs
```

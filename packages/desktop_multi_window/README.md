# desktop_multi_window

[![Pub](https://img.shields.io/pub/v/desktop_multi_window.svg)](https://pub.dev/packages/desktop_multi_window)

A Flutter plugin to create and manage multiple windows on desktop platforms.

|         |     | 
|---------|-----|
| Windows | ✅   | 
| Linux   | ✅   |  
| macOS   | ✅   | 

## Installation

Add `desktop_multi_window` to your `pubspec.yaml`:

```yaml
dependencies:
  desktop_multi_window: ^latest_version
```

## Getting Started

### 1. Initialize Multi-Window Support

In your `main()` function, initialize multi-window support before running your app:

```dart
import 'package:desktop_multi_window/desktop_multi_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get the current window controller
  final windowController = await WindowController.fromCurrentEngine();
  
  // Parse window arguments to determine which window to show
  final arguments = parseArguments(windowController.arguments);
  
  // Run different apps based on the window type
  switch (arguments.type) {
    case YourArgumentDefinitions.main:
      runApp(const MainWindow());
    case YourArgumentDefinitions.sample:
      runApp(const SampleWindow());
    // Add more window types as needed
  }
}
```

### 2. Create New Windows

Use `WindowController.create()` to create and manage new windows:

```dart
// Create a new window
final controller = await WindowController.create(
  WindowConfiguration(
    hiddenAtLaunch: true,
    arguments: 'YOUR_WINDOW_ARGUMENTS_HERE',
  ),
);

// Show the window (if hidden at launch)
await controller.show();
```

### 3. Manage Existing Windows

Get all window controllers and manage them:

```dart
// Get all windows
final controllers = await WindowController.getAll();

// Find a specific window by business ID
for (var controller in controllers) {
  final args = parseArguments(controller.arguments);
  // Check window type
  if (args.type == YourArgumentDefinitions.sample) {
    await controller.center();
    await controller.show();
    return;
  }
}

// Listen to window changes
onWindowsChanged.listen((_) {
  // Handle window changes
});
```

### 4. Communication Between Windows

Use `WindowMethodChannel` for bidirectional communication between windows:

```dart
// In the target window, set up a method call handler
const channel = WindowMethodChannel('my_channel');
channel.setMethodCallHandler((call) async {
  switch (call.method) {
    case 'play':
      // Handle the method call
      return 'success';
    default:
      throw MissingPluginException('Not implemented: ${call.method}');
  }
});

// From another window, invoke methods
const channel = WindowMethodChannel('my_channel');
final result = await channel.invokeMethod('play');
```

### 5. Extend WindowController with Custom Methods

Create an extension to add custom functionality:

```dart
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

extension WindowControllerExtension on WindowController {
  Future<void> doCustomInitialize() async {
    return await setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_center':
          return await windowManager.center();
        case 'window_close':
          return await windowManager.close();
        default:
          throw MissingPluginException('Not implemented: ${call.method}');
      }
    });
  }
  
  Future<void> center() {
    return invokeMethod('window_center');
  }
  
  Future<void> close() {
    return invokeMethod('window_close');
  }
}
```

And now, you can center or close the window in the other window:

```dart
final controller = await WindowController.fromWindowId(other_window_id);

// Center the window
await controller.center();

// Close the window
await controller.close();
```

## Working with Plugins in Sub-Windows

Each window created by this plugin has its own dedicated Flutter engine. Method channels cannot be shared between engines, so plugins must be manually registered for each new window.

### Platform-Specific Plugin Registration

#### Windows

Edit `windows/runner/flutter_window.cpp`:

1. Add the include at the top of the file:

```diff
 #include "flutter_window.h"
 
 #include <optional>
 
 #include "flutter/generated_plugin_registrant.h"
+#include "desktop_multi_window/desktop_multi_window_plugin.h"
```

2. Register the callback in the `OnCreate()` method:

```diff
   RegisterPlugins(flutter_controller_->engine());
+  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
+    auto *flutter_view_controller =
+        reinterpret_cast<flutter::FlutterViewController *>(controller);
+    auto *registry = flutter_view_controller->engine();
+    RegisterPlugins(registry);
+  });
   SetChildContent(flutter_controller_->view()->GetNativeWindow());
```

The `RegisterPlugins` function will automatically register all plugins for each new window.

#### macOS

Edit `macos/Runner/MainFlutterWindow.swift`:

1. Add the import at the top of the file:

```diff
 import Cocoa
 import FlutterMacOS
+import desktop_multi_window
```

2. Register the callback in the `awakeFromNib()` method:

```diff
     RegisterGeneratedPlugins(registry: flutterViewController)
     
+    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
+      // Register the plugin which you want access from other isolate.
+      RegisterGeneratedPlugins(registry: controller)
+    }
+
     super.awakeFromNib()
```

The `RegisterGeneratedPlugins` function will automatically register all plugins for each new window.

#### Linux

Edit `linux/my_application.cc`:

1. Add the include at the top of the file:

```diff
 #include "my_application.h"
 
 #include <flutter_linux/flutter_linux.h>
 #ifdef GDK_WINDOWING_X11
 #include <gdk/gdkx.h>
 #endif
 
 #include "flutter/generated_plugin_registrant.h"
 
+#include "desktop_multi_window/desktop_multi_window_plugin.h"
```

2. Register the callback in the `my_application_activate()` function:

```diff
   fl_register_plugins(FL_PLUGIN_REGISTRY(view));
 
+  desktop_multi_window_plugin_set_window_created_callback([](FlPluginRegistry* registry){
+    fl_register_plugins(registry);
+  });
+
   gtk_widget_grab_focus(GTK_WIDGET(view));
```

The `fl_register_plugins` function will automatically register all plugins for each new window.

## Integration with window_manager

This plugin works great with [window_manager](https://pub.dev/packages/window_manager) to control window properties:

by now, you should this fork version with a bit fix

```yaml
  window_manager:
    git:
      url: https://github.com/boyan01/window_manager.git
      path: packages/window_manager
      ref: 6fae92d21b4c80ce1b8f71c1190d7970cf722bd4
```

```dart
import 'package:window_manager/window_manager.dart';

// Configure window options
WindowOptions windowOptions = const WindowOptions(
  size: Size(800, 600),
  center: true,
  backgroundColor: Colors.transparent,
  skipTaskbar: false,
  titleBarStyle: TitleBarStyle.hidden,
);

windowManager.waitUntilReadyToShow(windowOptions, () async {
  await windowManager.show();
  await windowManager.focus();
});

// Prevent window from closing immediately
windowManager.setPreventClose(true);
windowManager.addListener(this); // Must implement WindowListener
```

## Example

Check out the [example](example) directory for a complete working application that demonstrates:
- Creating multiple window types
- Single instance vs multi-instance windows
- Communication between windows
- Custom window extensions
- Plugin registration for video playback
- Window lifecycle management

## License

MIT

# desktop_multi_window

[![Pub](https://img.shields.io/pub/v/desktop_multi_window.svg)](https://pub.dev/packages/desktop_multi_window)

A flutter plugin to create and manage multi window in desktop.

|         |     | 
|---------|-----|
| Windows | ✅   | 
| Linux   | ✅   |  
| macOS   | ✅   | 

## Usage

To use this plugin, add `desktop_multi_window` as a dependency in your pubspec.yaml file.

## Example

### Create and Show another window.

```
final window = await DesktopMultiWindow.createWindow(jsonEncode({
  'args1': 'Sub window',
  'args2': 100,
  'args3': true,
  'bussiness': 'bussiness_test',
}));
window
  ..setFrame(const Offset(0, 0) & const Size(1280, 720))
  ..center()
  ..setTitle('Another window')
  ..show();
```

### Invoke remote window method.

The windows run on different flutter engine. So we need to use `DesktopMultiWindow.setMethodCallHandler`
and `DesktopMultiWindow.invokeMethod` to handle method calls between windows.

```
DesktopMultiWindow.setMethodCallHandler((call, fromWindowId) async {
  debugPrint('${call.method} ${call.arguments} $fromWindowId');
  return "result";
});
```

```
final result =
    await DesktopMultiWindow.invokeMethod(windowId!, "method_name", "arguments");
debugPrint("onSend result: $result");
```

### Use plugins in Sub window

Because each window created by this plugin has its own dedicated Flutter engine, and method channels cannot be shared between engines, the new window cannot directly call plugins registered with the main Flutter engine.

The solution is to manually register the required plugins.

https://github.com/MixinNetwork/flutter-plugins/blob/985d81661d00715a37ba1767ab2d22ff64641d43/packages/desktop_multi_window/example/windows/runner/flutter_window.cpp#L32-L38

https://github.com/MixinNetwork/flutter-plugins/blob/985d81661d00715a37ba1767ab2d22ff64641d43/packages/desktop_multi_window/example/macos/Runner/MainFlutterWindow.swift#L15-L18

https://github.com/MixinNetwork/flutter-plugins/blob/985d81661d00715a37ba1767ab2d22ff64641d43/packages/desktop_multi_window/example/linux/my_application.cc#L65-L69

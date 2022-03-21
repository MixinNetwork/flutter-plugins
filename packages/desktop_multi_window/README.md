# desktop_multi_window

[![Pub](https://img.shields.io/pub/v/desktop_multi_window.svg)](https://pub.dev/packages/desktop_multi_window)

A flutter plugin that create and manager multi window in desktop.

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

The windows run on different flutter engine. So we need use `DesktopMultiWindow.invokeMethod`
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

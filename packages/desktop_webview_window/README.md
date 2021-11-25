# desktop_webview_window

[![Pub](https://img.shields.io/pub/v/desktop_webview_window.svg)](https://pub.dev/packages/desktop_webview_window)

Show a webview window on your flutter deksktop application.

|          |       |     |
| -------- | ------- | ---- |
| Windows  | ✅     | [Webview2](https://www.nuget.org/packages/Microsoft.Web.WebView2) 1.0.992.28 |
| Linux    | ✅    |  [WebKitGTK](https://webkitgtk.org/reference/webkit2gtk/stable/index.html)
| macOS    | ✅     |  WKWebview |

## Getting Started

1. modify your `main` method.
   ```dart
   import 'package:desktop_webview_window/desktop_webview_window.dart';
   
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     
     // Add this your main method.
     // used to show a webview title bar.
     if (runWebViewTitleBarWidget(args)) {
       return;
     }
   
     runApp(MyApp());
   }
   
   ```

2. launch WebViewWindow

   ```dart
     final webview = await WebviewWindow.create();
     webview.launch("https://example.com");
   ```

### **linux requirement**

```shell
sudo apt install webkit2gtk-4.0
```

### **Windows requirement**

The backend of desktop_webview_window on Windows is WebView2, which requires **WebView2 Runtime** installed.

[WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2) is ship in box with Windows11, but
it may not installed on Windows10 devices. So you need consider how to distribute the runtime to your users.

See more: https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution

For convenience, you can use `WebviewWindow.isWebviewAvailable()` check whether the WebView2 is available.


## License

see [LICENSE](./LICENSE)

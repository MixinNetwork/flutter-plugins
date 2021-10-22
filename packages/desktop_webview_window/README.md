# desktop_webview_window

[![Pub](https://img.shields.io/pub/v/desktop_webview_window.svg)](https://pub.dev/packages/desktop_webview_window)

Show a webview window on your flutter deksktop application.

|          |       |     |
| -------- | ------- | ---- |
| Windows  | ✅     | [Webview2](https://www.nuget.org/packages/Microsoft.Web.WebView2) 1.0.992.28 |
| Linux    | ✅    |  [WebKitGTK](https://webkitgtk.org/reference/webkit2gtk/stable/index.html)
| macOS    | ✅     |  WKWebview |

## Getting Started

```dart
import 'package:desktop_webview_window/desktop_webview_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final webview = await WebviewWindow.create();
  webview.launch("https://example.com");
}

```

**linux requirement**

```shell
sudo apt install webkit2gtk-4.0
```

## License

see [LICENSE](./LICENSE)

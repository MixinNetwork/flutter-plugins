import 'extended_window_style.dart';
import 'window_style.dart';

class WindowsWindowOptions {
  final int style;
  final int exStyle;
  final int x;
  final int y;
  final int width;
  final int height;
  final String title;

  const WindowsWindowOptions({
    this.style = WindowsWindowStyle.WS_OVERLAPPED, // WS_OVERLAPPEDWINDOW
    this.exStyle = WindowsExtendedWindowStyle.NO_EX_STYLE,
    this.x = 10,
    this.y = 10,
    this.width = 1280,
    this.height = 720,
    this.title = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'style': style,
      'exStyle': exStyle,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'title': title,
    };
  }
}
